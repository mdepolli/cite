# Filtering RAG retrieval results

This guide builds a policy that reads the passages a retriever returns for
a query and keeps the ones that answer it. It runs before a model writes
from them, and before
[Checking RAG answers against their sources](checking-rag-answers.md),
which checks the answer once it is written.

It assumes you run a retrieval-augmented generation (RAG) system and have
not used Cite before. The query and passages below are invented.

## What you will build

A policy module, the code that runs it on one query, and a list like this:

| Candidate | Answers the query? |
|---|---|
| "A fed starter keeps in the fridge for about a week before it needs feeding again." | yes |
| "Refrigerated, an unfed starter survives for months; revive it with two or three feedings." | yes |
| "Sourdough starter is flour and water fermented by wild yeast and bacteria." | no |
| "Yeast slows down at fridge temperatures, which is why bakers refrigerate between bakes." | no |
| "How long does sourdough bread stay fresh? Most loaves keep three to four days." | no |
| "Read our full guide to storing starters for everything you need to know." | no |

The query was "how long does a sourdough starter keep in the fridge". All
six passages share its words, so any of them could top a retriever's list.
Only two say how long.

You write down what counts as an answer, pass each query's candidates in
the order the retriever returned them, and send the answering candidates
to your generator. Cite asks your question of every candidate and cites
the ones that fit.

## 1. Decide what counts

A candidate answers the query when a reader could write the answer from it
alone: the fact, figure, date, name, place, definition, explanation, or
steps the query asks for.

- **An approximate answer counts.** "About a week" and "for months" both
  answer "how long". So do a range, a typical value, or an answer in other
  words than the query's.
- **The subject is not the answer.** A passage about sourdough starters
  that says what they are, or why bakers refrigerate them, is on topic and
  answers nothing.
- **A near match is a different thing.** Bread is not a starter. A passage
  about another product, person, place, or sense of the query's words does
  not answer it.
- **Questions and pointers are not answers.** A passage that repeats the
  query, lists related questions, or sends the reader elsewhere does not
  state what was asked.
- **Judge what the passage states, not whether it is true.** Checking the
  answer against the world is a different job.

## 2. Turn retrieval results into a source

One query is one source, and each candidate is one passage. The query goes
in each candidate's `meta`:

```elixir
query = "how long does a sourdough starter keep in the fridge"

retrieved = [
  %{text: "A fed starter keeps in the fridge for about a week before it needs feeding again.", url: "https://example.com/starter-care"},
  %{text: "Sourdough starter is flour and water fermented by wild yeast and bacteria.", url: "https://example.com/what-is-a-starter"},
  # ...
]

candidates =
  retrieved
  |> Enum.with_index(1)
  |> Enum.map(fn {%{text: text, url: url}, rank} ->
    %{id: "r#{rank}", text: text, meta: %{query: query, url: url}}
  end)

source = Cite.source(candidates, as: "candidates", show: [:query])
```

- **Keep the retriever's order.** Ids such as `r1`, `r2` record the
  retriever's rank, so you can compare it with what Cite keeps.
- **Show the query, not the URL.** The question is what the passage says.
  Where it came from is for you, so keep the URL in `meta`, unshown.
- **Copy the query onto every candidate.** A request has no place for
  context shared by the whole run. Each candidate carries its own copy, and
  `show:` lets the model see it.
- **Keep duplicates.** Retrievers often return the same text twice. Pass
  it as you received it, and drop repeats after Cite has judged them.

## 3. Write the concern

One concern, with a detect: a yes/no question asked of every candidate. A
placeholder cannot name meta, so the question names the candidate as
`{passage}` and the query in words:

```elixir
concern :answers_query do
  detect do
    question "Does {passage} answer the query shown with it?"

    yes do
      what "The passage states what the query asks for, so an answer could be written from it alone: the fact, figure, date, name, place, definition, explanation, or steps sought. It may say more than was asked, or answer in other words."

      not_for "A passage on the query's topic that does not state what was asked: one that repeats the query's words, asks the same question, lists related questions, or points elsewhere for the answer; a passage about a different person, place, product, or sense of the query's words."
    end

    no "The passage does not state what the query asks for, though it may share its words or topic."
  end
end
```

This first wording held up. Every change tried after it did not. These
rules came out of those tries:

- **Judge a query's candidates together.** At the default `window`, up to
  40 of a query's candidates go in one request. Judging each alone was no
  more precise, found fewer answers, and cost more.
- **Measure a rerun before crediting a change.** Two runs of the same
  policy differ by a few false alarms. A rewording that changes fewer than
  that has changed nothing.
- **Stop rewording when every wording makes the same false alarms.** The
  false alarms that survived here were passages about the query's
  subject, read as answers under every wording, whether judged together
  or alone. That is how the model reads the concept, not a gap in the
  question.
- **A narrower second question costs real answers.** A confirm that asked
  for "the specific answer" cleared some of those false alarms. It also
  sent sound answers to review, such as a price range for a cost.

The full policy is at the end of this guide. More on the language in
[Writing policies](../writing-policies.md).

## 4. Run it

```elixir
client = Cite.client(Cite.Provider.TypeSafe, api_key: System.fetch_env!("TYPESAFE_API_KEY"))
report = Cite.judge(client, source, MyApp.Relevance)
```

A query with ten candidates is one screening request, then one judging
request if any candidate matched. Each query is its own source, so run one
query per call.

## 5. From findings to context

The finding cites the candidates that answer the query. Each citation keeps
the model's round-2 answer, so you can order them by it:

```elixir
defmodule MyApp.Context do
  alias Cite.{Citation, Finding, Report}

  # The texts of the candidates that answer the query, most confident
  # first; :unchecked when a request failed.
  def answering(%Report{errors: [_ | _]}), do: :unchecked

  def answering(%Report{findings: findings}) do
    held =
      for %Finding{concern: :answers_query, evidence: evidence} <- findings,
          %Citation{verdict: :holds, passage: passage, answer: answer} <- evidence,
          do: {answer["noul"], passage.text}

    held
    |> Enum.sort_by(fn {p, _text} -> p end, :desc)
    |> Enum.map(fn {_p, text} -> text end)
    |> Enum.uniq()
  end
end
```

- **When nothing holds, nothing answers.** Say so, or retrieve again,
  rather than let the generator write from passages that only share the
  topic.
- **Decide what review means for you.** A `:review` candidate is one the
  model was unsure of. Leave it out of the context, or add it after the
  held ones.
- **A failed request means the query was not checked.** Its candidates
  land in `report.errors`. Fall back to the retriever's own order, or
  retry.

### Ordering every candidate

To order all of a query's candidates, not just the answers, sort them by
their round-1 score. `report.screen` keeps it for every candidate:

```elixir
ordered =
  Enum.sort_by(source.passages, &(report.screen[&1.id][:answers_query] || 0.0), :desc)
```

Sorted this way, an answer came first far more often than in the order the
candidates arrived in, or when ranked by how many of the query's words they
share. When the top candidate was not an answer, it was on the query's
subject, like the policy's false alarms, or the query was too vague to say
what an answer is. No dedicated reranking model was compared.

## 6. Check it against labels

MS MARCO holds real search queries, each with the passages a search engine
retrieved for it. Annotators marked the passages they wrote an answer
from. Its terms allow non-commercial research only, and grant no licence to
the passages themselves.

- **Check the negatives before you trust precision.** The annotators marked
  the passage they used, not every passage that answers. Many unmarked
  candidates answer the query, and some marked ones do not. A second
  reading, blind to the results, is the reference to measure precision
  against. Keep it apart from the annotators' labels, and never merge the
  two.
- **Word overlap is a weak baseline here.** The baseline cites a candidate
  when enough of the query's words appear in it. Every candidate was
  retrieved for those words, so the rule cites answers and near misses
  alike. It finds many of the answers, and flags much of what does not
  answer.

Keep some queries aside that you never read while rewording.
[Tuning against labels](../writing-policies.md#tuning-against-labels) has
the method.

## 7. When not to use Cite

If you only need the retriever's top few passages reordered, a reranking
model gives every candidate a score in milliseconds, and Cite does not.

Cite earns its place where you want a decision per candidate, answers or
not, made by a rule in your own words. Use it to drop what does not
answer, to say "nothing found" instead of guessing, or to audit what your
retriever returns.

## The whole policy

```elixir
defmodule MyApp.Relevance do
  use Cite.Policy

  concern :answers_query do
    detect do
      question "Does {passage} answer the query shown with it?"

      yes do
        what "The passage states what the query asks for, so an answer could be written from it alone: the fact, figure, date, name, place, definition, explanation, or steps sought. It may say more than was asked, or answer in other words."

        not_for "A passage on the query's topic that does not state what was asked: one that repeats the query's words, asks the same question, lists related questions, or points elsewhere for the answer; a passage about a different person, place, product, or sense of the query's words."
      end

      no "The passage does not state what the query asks for, though it may share its words or topic."
    end
  end
end
```
