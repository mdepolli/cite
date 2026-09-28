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
| "The frame and motor are covered for three years." | evident conflict |
| "Kestrel will replace a faulty battery." | subtle conflict |
| "Claims are usually settled within five working days." | evident baseless info |
| "That makes the K2 one of the best-covered e-bikes you can buy." | subtle baseless info |

All five sentences read well. Four of them are wrong about the documents
the answer came from, which you will see in step 2. Spotting them takes
reading each claim against those documents.

You write down what counts as each kind of problem, split the answer into
sentences, copy the question and documents onto each, and turn the findings
into the table. Cite asks your questions of every sentence and cites the
ones that fit.

## 1. Decide what counts

The input is what the answering model was given: the question and the
retrieved documents. Two questions sort the problems in an answer: does the
input say otherwise, or say nothing? And can you see the problem by putting
the two side by side, or does it take a judgement call?

- **Evident conflict**: a fact the input states differently. A wrong or
  misspelled name, a wrong number, date, or place, the wrong person acting,
  or the opposite of what the input says. "Covered for three years", where
  the documents say two.
- **Subtle conflict**: a restatement whose word or framing changes the
  implication or severity. A suspicion stated as a finding, a possibility
  as a certainty, one side's claim as fact, a milder or harsher term. The
  documents say Kestrel "may" replace a faulty battery; the answer says it
  "will".
- **Evident baseless info**: a concrete fact the input never mentions. A
  name, number, date, event, quotation, or feature. "Settled within five
  working days", when no document mentions timing.
- **Subtle baseless info**: what a writer might infer or assume. A judgement
  or sentiment, a motive, a consequence, a general norm, or background
  knowledge. "One of the best-covered e-bikes you can buy."

Then settle the boundaries:

- **Judge against the input, not the world.** A fact that is true but
  absent from the input is baseless. You are checking whether the answer
  came from its sources, not whether it is correct.
- **A faithful paraphrase is not a problem.** Only a changed meaning is.
- **A sentence can hold two problems.** "The frame is covered for three
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
one string:

```elixir
input = """
Question: What does the Kestrel K2 warranty cover?

document 1: The Kestrel K2 comes with a two-year warranty on the frame and motor. The battery is covered for 500 charge cycles or 18 months, whichever comes first.

document 2: Warranty claims must go through an authorised dealer and need proof of purchase. Kestrel may repair or replace a faulty battery, at its discretion.

document 3: Kestrel offers an extended warranty for the frame, adding three years, for $79.
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

## 3. Write one concern per kind of problem

Each kind is a concern with a detect: a yes/no question asked of every
sentence. A placeholder cannot name meta, so the question names the
sentence as `{passage}` and the input in words:

```elixir
concern :evident_conflict do
  detect do
    question "Does {passage} contain any claim that the input shown with it plainly contradicts?"

    yes do
      what "Some part of the sentence, however small, states a fact the input states differently: a wrong or misspelled name, a wrong number, date, place, or who did what, or the opposite of what the input says. Comparing the two shows the error without interpretation. The rest of the sentence may be accurate."

      not_for "A claim that shifts the input's meaning only by implication, emphasis, or severity (a subtle conflict); a claim the input neither states nor contradicts, whether a concrete fact or an inference (baseless information)."
    end

    no "No claim in the sentence contradicts the input plainly."
  end
end
```

Three choices shape all four concerns:

- **Ask whether the sentence contains a problem, not whether it is one.**
  A sentence with one wrong figure among three right ones is mostly
  accurate. Asked "is this sentence contradicted?", a model can fairly say
  no. Asked "does it contain any claim that is?", it has to find the one.
  "However small" and "the rest of the sentence may be accurate" say the
  same in the criteria.
- **Keep neighbouring kinds apart in the `yes`.** Each `yes` names the
  other three kinds in its `not_for`. It excludes claims, not sentences,
  so a sentence with two kinds of problem is still cited under both.
- **Keep the `no` to one line.** It covers the sentence with no such
  claim. The boundaries are already in the `yes`.

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
then one judging request per kind of problem found.

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
- **Decide what each kind costs you.** You might block an answer on an
  evident conflict and only flag subtle baseless info. That call lives in
  your code; Cite reports all four the same way.
- **Review goes to a person.** Show a `:review` sentence beside the input
  it was checked against.

## 6. Check it against labels

RAGTruth holds answers from several models, each with the input it was
written from. Annotators marked every problem as a span of the answer, with
one of the four kinds above. Its code and labels are MIT; its documents
come from MS MARCO and news articles, under their own terms.

- **Your label rule must ask your question.** Spans do not follow
  sentences, so turn them into sentence labels by a rule. A sentence gets
  every kind whose span overlaps it; a sentence no span touches is labelled
  none, so false alarms count. The rule marks a long sentence with a
  three-word problem, which is why the questions ask whether a sentence
  *contains* one.
- **Watch sentences cited under two kinds but labelled with one.** They
  show where neighbouring kinds bleed into each other; the fix is in the
  `yes`'s `not_for`.
- **Score the axes apart.** Whether a sentence has any problem, and whether
  its kind is right, are two scores. A policy can be good at the first and
  still confuse evident with subtle.

Score a word-overlap check beside the policy: cite a sentence when enough
of its words are missing from the input. Citing any unseen word flags
almost every sentence, because answers paraphrase. Tune the share on your
training labels, not on the ones you hold out.

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

  concern :evident_conflict do
    detect do
      question "Does {passage} contain any claim that the input shown with it plainly contradicts?"

      yes do
        what "Some part of the sentence, however small, states a fact the input states differently: a wrong or misspelled name, a wrong number, date, place, or who did what, or the opposite of what the input says. Comparing the two shows the error without interpretation. The rest of the sentence may be accurate."

        not_for "A claim that shifts the input's meaning only by implication, emphasis, or severity (a subtle conflict); a claim the input neither states nor contradicts, whether a concrete fact or an inference (baseless information)."
      end

      no "No claim in the sentence contradicts the input plainly."
    end
  end

  concern :subtle_conflict do
    detect do
      question "Does {passage} contain any claim that changes the meaning of something the input shown with it says, without plainly contradicting it?"

      yes do
        what "Some part of the sentence, however small, restates the input with a word or framing that carries a different implication or severity: a suspicion stated as a finding, a possibility as a certainty, one side's claim as fact, a milder or harsher term than the input's. The rest of the sentence may be accurate."

        not_for "A claim with a plainly wrong name, number, date, or fact (an evident conflict); a claim about something the input does not mention at all (baseless information)."
      end

      no "No claim in the sentence restates the input with a changed meaning."
    end
  end

  concern :evident_baseless_info do
    detect do
      question "Does {passage} contain any specific fact or detail that the input shown with it does not contain?"

      yes do
        what "Some part of the sentence, however small, adds a concrete claim with no support in the input: a name, number, date, event, quotation, feature, or other fact the input never mentions, whether or not it is true in the world. The rest of the sentence may be supported."

        not_for "A claim the input states differently, plainly or by implication (a conflict); an inference, opinion, or piece of general knowledge drawn from what the input says (subtle baseless information)."
      end

      no "Every concrete fact in the sentence is in the input."
    end
  end

  concern :subtle_baseless_info do
    detect do
      question "Does {passage} contain any inference, opinion, or assumption that goes beyond what the input shown with it says?"

      yes do
        what "Some part of the sentence, however small, adds what the input does not state but a writer might infer or assume: a judgment or sentiment, a motive, a consequence, a general norm, or background knowledge, such as describing a place as popular or explaining why something happened. The rest of the sentence may be supported."

        not_for "A concrete name, number, date, or event the input never mentions (evident baseless information); a claim the input states differently, plainly or by implication (a conflict)."
      end

      no "The sentence adds no inference, opinion, or assumption to what the input says."
    end
  end
end
```
