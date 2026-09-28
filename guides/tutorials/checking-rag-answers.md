# Checking RAG answers against their sources

This guide builds a policy that finds hallucinations in answers from a
retrieval-augmented generation (RAG) system: claims the retrieved documents
contradict, and claims they never make. Each problem comes back with the
sentence that makes it, so you can block the answer, regenerate it, or show
it with a warning.

It assumes you run a RAG system and have not used Cite before. The answer
and documents below are invented.

## What you will build

A policy module, the code that runs it on one answer, and a table like
this:

| Sentence | Problem |
|---|---|
| "The K2's battery is covered for 500 charge cycles or 18 months, whichever comes first." | none found |
| "The frame and motor are covered for three years." | conflict |
| "Kestrel will replace a faulty battery." | conflict |
| "Claims are usually settled within five working days." | baseless info |
| "That makes the K2 one of the best-covered e-bikes you can buy." | baseless info |

All five sentences read well. Four of them are wrong about the documents
the answer came from, which you will see in step 2. Spotting them takes
reading each claim against those documents.

You write down what counts as each kind of problem, split the answer into
sentences, copy the question and documents onto each, and turn the findings
into the table. Cite asks your questions of every sentence and cites the
ones that fit.

## 1. Decide what counts

The input is what the answering model was given: the question and the
retrieved documents. One question sorts the problems in an answer: does the
input say otherwise, or say nothing?

- **Conflict**: the answer changes something the input says. A wrong name,
  number, date, or place, or the wrong person acting; the opposite of what
  the input says; or a word that changes its meaning, such as a possibility
  stated as a certainty, a reported claim stated as fact, a dropped hedge,
  or a changed bound. "Covered for three years", where the documents say
  two. Kestrel "will" replace a faulty battery, where the documents say it
  "may".
- **Baseless info**: the answer adds what the input does not say. A
  concrete fact it never mentions, or an inference, opinion, or piece of
  background knowledge beyond it. "Settled within five working days", when
  no document mentions timing. "One of the best-covered e-bikes you can
  buy."

Then settle the boundaries:

- **Judge against the input, not the world.** A fact that is true but
  absent from the input is baseless. You are checking whether the answer
  came from its sources, not whether it is correct.
- **A faithful paraphrase is not a problem.** Only a changed meaning is.
- **A wrong statement about the input is a conflict.** "The documents do
  not say how long claims take" is fine when they don't, and a conflict
  when they do. "I cannot answer from these documents" is a conflict too,
  when they do answer the question.
- **A sentence that asserts nothing is not checked.** "I hope this helps!"
  and "Here is my answer:" make no claim that could be wrong.
- **A sentence can hold both problems.** "The frame is covered for three
  years, and claims settle in a week" is a conflict and baseless info. It
  counts under both.

## 2. Turn an answer into a source

One answer is one source, and one sentence is one passage:

```elixir
defmodule MyApp.Sentences do
  # A sentence ends at a line break, or after ., !, or ? (with any closing
  # quote or bracket, and any bracketed citation such as "(document 2)")
  # when a space and a capital, digit, or opening quote follow.
  @sentence_end ~r/[.!?]["'”’)\]]*(?:\s+\([^()\n]*\))?(?=\s+[\p{Lu}\p{N}"“])|\n/u

  def split(answer) do
    ends =
      for [{start, length}] <- Regex.scan(@sentence_end, answer, return: :index),
          do: start + length

    [0 | ends]
    |> Enum.concat([byte_size(answer)])
    |> Enum.uniq()
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [from, to] -> String.trim(binary_part(answer, from, to - from)) end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce([], &join_marker/2)
    |> Enum.reverse()
  end

  # A piece with no letter, such as a list number, joins the sentence after it.
  defp join_marker(piece, [previous | rest]) do
    if Regex.match?(~r/\p{L}/u, previous),
      do: [piece, previous | rest],
      else: [previous <> " " <> piece | rest]
  end

  defp join_marker(piece, []), do: [piece]
end
```

- **Split by a rule you can apply to any answer.** Sentences work: a claim
  rarely spans two, and a finding then cites the sentence to fix.
- **Keep a citation with its claim.** "(document 2)" after a full stop
  belongs to the sentence before it. Cut on its own, it makes a sentence
  with no claim. A concern may still cite it.
- **Join a list number to the sentence after it.** "1." on its own line is
  not a sentence.
- **Know the rule's cost.** It splits "Dr. Smith" after "Dr.". Use a proper
  sentence splitter if your answers are full of abbreviations.

The question and the retrieved documents go in each sentence's `meta`, as
one string. `answer` is the text being checked:

```elixir
input = """
Question: What does the Kestrel K2 warranty cover?

document 1: The Kestrel K2 comes with a two-year warranty on the frame and motor. The battery is covered for 500 charge cycles or 18 months, whichever comes first.

document 2: Warranty claims must go through an authorised dealer and need proof of purchase. Kestrel may repair or replace a faulty battery, at its discretion.

document 3: Kestrel offers an extended warranty for the frame, adding three years, for $79.
"""

answer = """
The K2's battery is covered for 500 charge cycles or 18 months, whichever comes first.
The frame and motor are covered for three years.
Kestrel will replace a faulty battery.
Claims are usually settled within five working days.
That makes the K2 one of the best-covered e-bikes you can buy.
"""

sentences =
  answer
  |> MyApp.Sentences.split()
  |> Enum.with_index(1)
  |> Enum.map(fn {text, n} -> %{id: "s#{n}", text: text, meta: %{input: input}} end)

source = Cite.source(sentences, as: "sentences", show: [:input])
```

- **Show the input as your system gave it.** The question and documents,
  in one string, as the answering model read them.
- **Copy it onto every sentence.** A request has no place for context
  shared by the whole run. Each sentence carries its own copy, and `show:`
  lets the model see it.

## 3. Write the policy

A filter sets aside sentences that assert nothing. Then each kind of
problem is a concern with a detect: a yes/no question asked of every
sentence left. A placeholder cannot name meta, so each question names the
sentence as `{passage}` and the input in words:

```elixir
concern :conflict do
  detect do
    question "Does {passage} contain any claim that the input shown with it states differently?"

    focus "Check every number, date, qualifier, and attribution in {passage} against the input's own words: a dropped 'perhaps', 'reportedly', or 'as many as' changes the claim."

    yes do
      what "Some part of the sentence, however small, changes something the input says: a wrong or misspelled name, a wrong number, date, place, or who did what; the opposite of what the input says; a word or framing that changes its meaning or severity, such as a suspicion stated as a finding, a possibility as a certainty, a reported claim ('he reportedly said he spent') stated as fact, a hedge dropped ('perhaps best known' as 'best known'), or a bound changed ('as many as 900' as 'over 900', 'almost 22,000' as 'over 22,000'); or a wrong statement about what the input or one of its passages says, including 'unable to answer' or 'the passages do not say' when they do. The rest of the sentence may be accurate."

      not_for "A restatement in other words that keeps the input's meaning: a paraphrase, a shortened summary, or facts in another order; a claim about something the input does not mention at all (baseless information)."
    end

    no "No claim in the sentence states differently what the input says."
  end
end
```

These rules held up in practice:

- **Split a kind only where two readers agree.** RAGTruth, a public set of
  labelled answers, splits each kind into evident and subtle. Two careful
  readings of the same answers barely agreed on that split, and a policy
  that asked it cited sentences twice or under the wrong kind. With two
  concerns it was more precise, and cheaper.
- **Point the model at the words that change a claim.** The criteria
  already named a dropped hedge and a changed bound, and the model still
  passed "reportedly said he spent" restated as "spent". A `focus` on
  every number, date, qualifier, and attribution caught many of those.
- **Ask whether the sentence contains a problem, not whether it is one.**
  A sentence with one wrong figure among three right ones is mostly
  accurate. Asked "is this sentence contradicted?", a model can fairly say
  no. Asked "does it contain any claim that is?", it has to find the one.
  "However small" and "the rest of the sentence may be accurate" say the
  same in the criteria.
- **Rule out restatement in both concerns.** Each `not_for` opens with a
  restatement that keeps the input's meaning, then sends the other
  concern's cases away. It excludes claims, not sentences, so a sentence
  with both kinds of problem is cited under both.
- **Name what the filter must keep.** Its `yes` keeps "the passages do not
  mention the cost", which is a conflict when they do. Few false alarms
  came from sentences that assert nothing. The filter is there to keep
  "Sure!" away from your reviewers.

The full policy is at the end of this guide. More on the language in
[Writing policies](../writing-policies.md).

## 4. Run it

```elixir
client = Cite.client(Cite.Provider.TypeSafe, api_key: System.fetch_env!("JEV_API_KEY"))
report = Cite.judge(client, source, MyApp.Grounding, window: 1)
```

Every sentence carries the full input, so a window of 40 sentences would
send it 40 times in one request. At `window: 1`, each request holds one
sentence and one copy. A five-sentence answer is five screening requests,
each asking the filter and both concerns, then one judging request per
kind of problem found.

## 5. From findings to a table

Each finding is one kind of problem, citing the sentences that contain it:

```elixir
defmodule MyApp.Grounding.Review do
  alias Cite.{Citation, Finding, Passage, Report}

  # Each cited sentence id with its problems and their verdicts; :unchecked
  # when a request failed.
  def problems(%Report{errors: [_ | _]}), do: :unchecked

  def problems(%Report{findings: findings}) do
    for %Finding{concern: problem, evidence: evidence} <- findings,
        %Citation{passage: %Passage{id: id}, verdict: verdict} <- evidence,
        reduce: %{} do
      acc -> Map.update(acc, id, [{problem, verdict}], &[{problem, verdict} | &1])
    end
  end
end
```

- **A failed request leaves a sentence unchecked.** Its id lands in
  `report.errors`. An answer is grounded only if every sentence was read,
  so retry it or treat the answer as unchecked.
- **"None found" is relative to the input.** If retrieval missed the
  document that answers the question, a grounded answer can still be
  wrong. Cite checks the answer against what it was given.
- **Decide what each kind costs you.** You might block an answer on a
  conflict and only flag baseless info. That call lives in your code; Cite
  reports both the same way.
- **Review goes to a person.** Show a `:review` sentence beside the input
  it was checked against.

## 6. Check it against labels

RAGTruth holds answers from several models, each with the input it was
written from. Annotators marked every problem as a span of the answer, with
one of four kinds: conflict and baseless info, each evident or subtle. Read
them as the two kinds above. Its code and labels are MIT; its documents come
from MS MARCO and news articles, under their own terms.

- **Your label rule must ask your question.** Spans do not follow
  sentences, so turn them into sentence labels by a rule. A sentence gets
  every kind whose span overlaps it; a sentence no span touches is labelled
  none, so false alarms count. The rule marks a long sentence with a
  three-word problem, which is why the questions ask whether a sentence
  *contains* one.
- **Check the negatives before you trust precision.** Against RAGTruth,
  most sentences the policy cited looked like false alarms. A second
  reading, blind to the results and against the full input, found most of
  them were real problems the annotators left unlabelled. Keep such a
  reading as a reference of its own, score against both, and never merge
  the two.
- **Score any problem and the right kind apart.** A policy can find the
  problem sentences and still name the wrong kind. Sentences cited under
  both kinds but labelled with one show where; the fix is in the
  `not_for`.

Score a word-overlap check beside the policy: cite a sentence when enough
of its words are missing from the input. It only sees new words, so it
misses every conflict built from the input's own words ("as many as 900"
restated as "over 900", "unable to answer" when the documents answer). And
it flags faithful paraphrases, which use words the input does not. Tune
its share on your training labels, not on the ones you hold out.

Keep some answers aside that you never read while rewording.
[Tuning against labels](../writing-policies.md#tuning-against-labels) has
the method.

## 7. When not to use Cite

If your answers quote the input word for word, a string match against it
finds what is not quoted, and costs nothing. If you want to know whether
an answer is true, not whether it came from its input, Cite cannot tell
you: it reads only what you give it.

Mind the cost when the input is long. Every sentence carries it, so an
answer's cost grows with its sentence count times the length of its input.

## The whole policy

```elixir
defmodule MyApp.Grounding do
  use Cite.Policy

  filter :makes_a_claim do
    question "Does {passage} assert anything, about the subject of the answer or about what the input shown with it contains?"

    yes do
      what "The sentence states a fact, figure, event, step, description, judgment, or piece of advice about the subject, even behind framing such as 'Based on the passages, …'. So does a statement about what the input says or does not say, such as 'The passages do not mention the cost': it is wrong when the input does say it."
    end

    no "The sentence asserts nothing: a greeting or pleasantry ('I hope this helps!'), framing with nothing after it ('Here is my answer based on the given passages:'), a heading or list lead-in with no content ('The steps are:'), or a citation on its own."
  end

  concern :conflict do
    detect do
      question "Does {passage} contain any claim that the input shown with it states differently?"

      focus "Check every number, date, qualifier, and attribution in {passage} against the input's own words: a dropped 'perhaps', 'reportedly', or 'as many as' changes the claim."

      yes do
        what "Some part of the sentence, however small, changes something the input says: a wrong or misspelled name, a wrong number, date, place, or who did what; the opposite of what the input says; a word or framing that changes its meaning or severity, such as a suspicion stated as a finding, a possibility as a certainty, a reported claim ('he reportedly said he spent') stated as fact, a hedge dropped ('perhaps best known' as 'best known'), or a bound changed ('as many as 900' as 'over 900', 'almost 22,000' as 'over 22,000'); or a wrong statement about what the input or one of its passages says, including 'unable to answer' or 'the passages do not say' when they do. The rest of the sentence may be accurate."

        not_for "A restatement in other words that keeps the input's meaning: a paraphrase, a shortened summary, or facts in another order; a claim about something the input does not mention at all (baseless information)."
      end

      no "No claim in the sentence states differently what the input says."
    end
  end

  concern :baseless_info do
    detect do
      question "Does {passage} contain anything that the input shown with it does not say?"

      yes do
        what "Some part of the sentence, however small, adds what the input does not contain: a concrete name, number, date, event, quotation, feature, or step it never mentions; or an inference, opinion, judgment, motive, consequence, piece of advice, or background knowledge that goes beyond it, whether or not it is true in the world. The rest of the sentence may be supported."

        not_for "A restatement in other words that keeps the input's meaning: a paraphrase, a shortened summary, or facts in another order; a claim about something the input covers but gets wrong (a conflict)."
      end

      no "Everything in the sentence is stated or paraphrased in the input, or contradicted by it."
    end
  end
end
```
