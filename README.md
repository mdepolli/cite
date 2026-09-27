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
    detect do
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
error. [Writing policies](https://hexdocs.pm/cite/writing-policies.html) is
the full language; [Triaging logs](https://hexdocs.pm/cite/triaging-logs.html)
builds a policy from scratch.

**Hand over the source.** `Cite.source(units, opts)` takes the passages your
document already consists of: utterances, rows, paragraphs. A unit is a text
or `%{text: text, id: id, meta: meta}`. Text is kept byte for byte; missing
ids become `P000`, `P001`, and so on. `as:` names the passages in every
request (`"utterances"` reads better than the default `"passages"`), and
`show:` names the meta keys the model sees. Ids and `as` are part of every
path the model reads, so whitespace, invalid UTF-8, a `.`, a backtick, `[`
or `]` in one raises. Shown
meta goes on the wire, so a shown value that is not JSON (a struct, a tuple, a
pid) raises too. The rest of `meta` — timestamps your UI needs, say — stays
with you.

**Judge.** `Cite.judge(client, source, policy, opts)` runs two fixed rounds.
Round 1 screens every passage for every detect, a window of passages per
request. Between the rounds, fixed rules gather the matches into findings.
Round 2 judges each finding with one request on its own evidence.
[How judging works](https://hexdocs.pm/cite/how-judging-works.html) has the
requests and the verdict rules.

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
      dropped: []
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
every round-1 score and `dropped` every passage a finding's confirm turned away,
so a run is diagnosable without another request.

## Options

`threshold`, `review_band`, and `window` tune a run. Their defaults and
meaning are in the docs of `Cite.judge/4`, generated from the schema that
validates them. `threshold` does more than set recall: it decides which
passages are gathered, and a finding's confirms read all of them together,
so it changes verdicts too. Round 2 judges every passage gathered, one
request per finding, so its cost follows the threshold. See
[How judging works](https://hexdocs.pm/cite/how-judging-works.html).

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
one with a value its question cannot have, fails its whole request
(`{:missing_answers, keys}`, `{:malformed_answers, keys}`). A request the
provider refuses as too large is halved in round 1 and becomes the finding's
error in round 2.

## The client

```elixir
client = Cite.client(Cite.Provider.TypeSafe, api_key: System.fetch_env!("JEV_API_KEY"))
```

The client is a function, `request -> {:ok, verdict} | {:error, reason}`.
Build it once, where your credentials live, and pass it in. The request is
`%{"state" => map, "questions" => map}`, where a value in `"state"` may be a
`Cite.Wire.Object`, a JSON object that keeps its keys in order; the verdict is
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

Both rounds run for real; only the model is stubbed. That stub fits `Riddles`,
whose questions are all Nouls; a Score needs `%{"score" => level_index,
"confidence" => p}` and a Choice `%{"choice" => option_key, "confidence" =>
p}`, or the request fails as malformed. `Cite.Provider.TypeSafe`
itself is tested with [`Req.Test`](https://hexdocs.pm/req/Req.Test.html):
pass `req_options: [plug: {Req.Test, name}]` to `Cite.client/2`.

## Providers

`Cite.client/2` builds a client from any module implementing
`Cite.Provider`. `Cite.Provider.TypeSafe` ships with the library and talks to
[TypeSafe](https://typesafe.ai)'s Jev, what TypeSafe calls a System One
model. Its options, with their defaults, are in the docs of
`Cite.Provider.TypeSafe`, generated from the schema that validates them.

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
`Cite.Provider.TypeSafe` is stable through its documented options.
`Cite.Wire.Object`, which a request's `"state"` may hold, is stable as what
it implements: `Access` and `Jason.Encoder`.

**Internal**, no guarantees: the compiled policy structs, the Spark
extension, `Run`, `Screen`, `Gather`, `Judge`, `Placeholder`, `Wire`,
`Answer`. Their docs stay published because they explain how the library
works.

## License

MIT — see the
[LICENSE](https://github.com/mdepolli/cite/blob/main/LICENSE) file for
details.
