# Cite

[![Hex.pm](https://img.shields.io/hexpm/v/cite)](https://hex.pm/packages/cite)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue)](https://hexdocs.pm/cite)
[![CI](https://github.com/mdepolli/cite/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/mdepolli/cite/actions/workflows/ci.yml)

Judgments plus grounding. You declare a policy — what to look for in a
document, and what counts as a finding — and hand over the document's
passages. A decision model judges them, and Cite returns findings, each
citing your own passages, unchanged, for an end user to check.

The model answers typed questions about the passages: a probability, a
level, a choice. It never writes text, so it cannot misquote: every citation
is a passage you listed.

## Installation

```elixir
def deps do
  [
    {:cite, "~> 0.1.0"}
  ]
end
```

Cite uses [Req](https://hex.pm/packages/req) for HTTP and
[Spark](https://hex.pm/packages/spark) for the policy language. To format
policies without parentheses, add `import_deps: [:cite]` to your
`.formatter.exs`.

## Quick start

With a client (see [The client](#the-client)):

```elixir
defmodule Riddles do
  use Cite.Policy

  concern :riddle do
    indicator do
      question "Does {passage} pose a riddle?"
      yes "A question asked to be puzzled over, whether or not it has an answer."
      no "A plain question, a statement, or a remark."
    end
  end
end

source =
  Cite.source([
    "Why is a raven like a writing-desk?",
    "Take some more tea.",
    "Your hair wants cutting."
  ])

Cite.judge(client, source, Riddles)
```

Three steps: declare the policy once, hand over the source, judge the source
against the policy. The report holds one finding, `:riddle`, citing the
first line exactly as you gave it. The tea and the haircut were screened and
dropped, not paraphrased.

## The three steps

**Declare a policy.** A module that uses `Cite.Policy`. It declares
*concerns* (what a finding can be), and optionally *filters* (which passages
count at all), *factors* (facts that only count in combination), and
*descriptors* (a Score or Choice asked of every finding). Questions name what
they read by placeholder — `{passage}`, or a role like `{household}` — and
Cite writes the path the model sees. Every mistake in a policy is a compile
error. [Writing policies](guides/writing-policies.md) is the full language.

**Hand over the source.** `Cite.source(units, opts)` takes the passages your
document already consists of: utterances, rows, paragraphs. A unit is a text
or `%{text: text, id: id, meta: meta}`. Text is kept byte for byte; missing
ids become `P000`, `P001`, and so on. `as:` names the passages in every
request (`"utterances"` reads better than the default `"passages"`), and
`show:` names the meta keys the model sees. The rest of `meta` — timestamps
your UI needs, say — stays with you.

**Judge.** `Cite.judge(client, source, policy, opts)` runs two fixed rounds.
Round 1 screens every passage for every indicator, a window of passages per
request. Between the rounds, fixed rules gather the matches into findings.
Round 2 judges each finding with one request on its own evidence.
[How judging works](guides/how-judging-works.md) has the requests and the
verdict rules.

## The limits

They are part of the product:

- **Two fixed rounds.** A screen of every passage, then one judgment per
  finding. Nothing else is asked.
- **No question about the document as a whole.** A request holds a window of
  passages or one finding's evidence.
- **No passage you did not list.** Every finding is built from your source's
  passages.

## What comes back

```elixir
%Cite.Report{
  findings: [
    %Cite.Finding{
      concern: :riddle,
      category: :riddle,
      verdict: :holds,
      checks: %{},
      descriptors: %{},
      evidence: [
        %Cite.Citation{
          passage: %Cite.Passage{id: "P000", text: "Why is a raven like a writing-desk?"},
          verdict: :holds,
          answer: %{"noul" => 0.91}
        }
      ],
      dropped: [],
      over_cap: []
    }
  ],
  screen: %{"P000" => %{riddle: 0.94}, "P001" => %{riddle: 0.03}, "P002" => %{riddle: 0.02}},
  errors: [],
  usage: %{input_tokens: 812, output_tokens: 0},
  models: ["jev-1.13.0"]
}
```

A finding's `verdict` is `:holds`, `:review` (a person decides), or `:fails`,
and each citation carries its own. Answers are the model's raw maps: rounding
a Score, reading a Choice, and flooring on confidence are yours. `screen` is
every round-1 score and `dropped` every passage a finding's fit turned away,
so a run is diagnosable without another request.

## Options

| Option | Default | Meaning |
| ------ | ------- | ------- |
| `threshold` | `0.5` | round-1 score a match must exceed; sets recall only |
| `review_band` | `{0.4, 0.6}` | at or below `low` drops or fails; at or above `high` holds |
| `window` | `40` | passages per round-1 request |
| `max_evidence` | `20` | passages a finding may cite; the rest are `over_cap` |

## Errors

A mistake in a policy fails compilation. A mistake in the source or the
options raises `ArgumentError` in `Cite.source/2` or `Cite.judge/4`, before
the first request. Anything the model or the network did is a value:

```elixir
%Cite.Error{concern: :household_income, passage_ids: ["U003", "U009"], reason: :timeout}
```

A failed request is never a verdict. A screening window that fails leaves
its passages without a `screen` row (`concern: nil`); a finding whose request
fails is left out of `findings`. A reply that skips a question, or answers
one in a shape its type cannot have, fails its whole request
(`{:missing_answers, keys}`, `{:malformed_answers, keys}`). A request the
provider refuses as too large is halved in round 1 and becomes the finding's
error in round 2.

## The client

```elixir
client = Cite.client(Cite.Provider.TypeSafe, api_key: System.fetch_env!("JEV_API_KEY"))
```

The client is a function, `request -> {:ok, verdict} | {:error, reason}`.
Build it once, where your credentials live, and pass it in. The request is
`%{"state" => map, "questions" => map}`; the verdict is
`%{answers: map, usage: usage | nil}`, plus `model` when the provider reports
the versioned id that answered. Both shapes are part of the API.

## Testing without a key

A test's client is a function too:

```elixir
client = fn %{"questions" => questions} ->
  answers = Map.new(questions, fn {key, _question} -> {key, %{"noul" => 0.9}} end)
  {:ok, %{answers: answers, usage: nil}}
end

%Cite.Report{findings: findings} = Cite.judge(client, source, Riddles)
```

Both rounds run for real; only the model is stubbed. `Cite.Provider.TypeSafe`
itself is tested with [`Req.Test`](https://hexdocs.pm/req/Req.Test.html):
pass `req_options: [plug: {Req.Test, name}]` to `Cite.client/2`.

## Providers

`Cite.client/2` builds a client from any module implementing
`Cite.Provider`. `Cite.Provider.TypeSafe` ships with the library and talks to
[TypeSafe](https://typesafe.ai)'s Jev, what TypeSafe calls a System One
model. Its options: `:api_key` (or `JEV_API_KEY`), `:model`
(`"jev-1.13.0"`), `:base_url`, and `:req_options`, merged into the Req
client last.

A provider raises on your mistakes and returns `{:error, reason}` for
anything the network did. One reason is shared across providers,
`:request_too_large`, which is what round 1 halves windows on.

The TypeSafe provider retries rate limits (429), overloads (529), server
errors (500–504), and connection failures up to three times, honouring
`Retry-After` with delays capped at 30 seconds. Timeouts are not retried: a
120-second call retried is eight minutes, and a slow success would be billed
twice.

## Stability

The docs group modules by tier; SemVer applies to the **Core API** tier.

**Core API**, the contract: `Cite.client/2`, `Cite.source/2`,
`Cite.judge/4`; the policy language (`use Cite.Policy` and its
declarations); the structs you read — `Report`, `Finding`, `Citation`,
`Passage`, `Error`; and the client's request and verdict maps.

**Providers**: `Cite.Provider` is implementable; with one implementation in
the wild it may be reshaped in minor releases, changelog-noticed.
`Cite.Provider.TypeSafe` is stable through the options above.

**Internal**, no guarantees: the compiled policy structs, the Spark
extension, `Run`, `Screen`, `Gather`, `Judge`, `Placeholder`, `Wire`,
`Answer`. Their docs stay published because they explain how the library
works.

## License

MIT — see the
[LICENSE](https://github.com/mdepolli/cite/blob/main/LICENSE) file for
details.
