# ![](assets/logo.svg) Cite

[![Hex.pm](https://img.shields.io/hexpm/v/cite)](https://hex.pm/packages/cite)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue)](https://hexdocs.pm/cite)
[![CI](https://github.com/mdepolli/cite/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/mdepolli/cite/actions/workflows/ci.yml)

Cite finds what you describe in a document, such as failures in a log,
sponsor reads in a video's captions, or hallucinations in a RAG answer, and
cites the exact passages behind each one. It judges with a decision model,
not a generative LLM: no prompts, and no generated text.

You declare the questions in a small DSL and pass the document as the
passages it already has: log lines, caption chunks, conversation turns.
A decision model such as TypeSafe's Jev answers them for every passage.
Cite gathers the matches with fixed rules in code, then has the model judge
each match once with all of its passages in view.

A decision model answers with a probability for a yes-or-no question, a
level on a scale, or one option from a set, never with prose. Cite never
asks it to write, so it cannot misquote. Every finding is grounded in your
own passages, cited byte for byte.

## Installation

```elixir
def deps do
  [
    {:cite, "~> 0.1.0"}
  ]
end
```

Cite uses [Req](https://hex.pm/packages/req) for HTTP and
[Spark](https://hex.pm/packages/spark) for the DSL you write questions in.
To format that DSL without parentheses, add `import_deps: [:cite]` to your
`.formatter.exs`.

## Quick start

This example needs a TypeSafe API key. To try Cite without one, see
[Testing without a key](#testing-without-a-key).

```elixir
client = Cite.client(Cite.Provider.TypeSafe, api_key: System.fetch_env!("JEV_API_KEY"))

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

Cite finds one riddle and cites the line it came from. Here is the report,
trimmed to the fields that matter:

```elixir
%Cite.Report{
  findings: [
    %Cite.Finding{
      concern: :riddle,
      verdict: :holds,
      evidence: [
        %Cite.Citation{
          passage: %Cite.Passage{id: "P000", text: "Why is a raven like a writing-desk?"},
          verdict: :holds,
          answer: %{"noul" => 0.91}
        }
      ]
    }
  ],
  screen: %{"P000" => %{riddle: 0.94}, "P001" => %{riddle: 0.03}, "P002" => %{riddle: 0.02}}
}
```

The other two lines were checked and left out. Their scores are in
`screen`, so you can see why.

## How it works

A **policy** says what to look for. It is a module that lists
**concerns**, one for each kind of thing you want found: a riddle, a kernel
crash, a sponsor read. The simplest concern asks one yes-or-no question of
every passage. A policy can also have filters, factors, and descriptors;
[Writing policies](https://hexdocs.pm/cite/writing-policies.html) covers
them all.

A **source** is your text, split into passages. `Cite.source/2` keeps each
passage exactly as you gave it. `as:` names the passages ("lines",
"utterances"). `show:` lets the model see fields from each passage's
`meta`, such as who said a line. Beyond a passage's id and text, the model
sees only those fields. A request has no place for context about the whole
run. Put a value every passage shares, such as the question they are judged
against, in each passage's `meta` and name it in `show:`.

`Cite.judge/4` runs the policy over the source in two rounds. First it asks
every question about every passage. Then it groups the passages that
matched into **findings** and judges each finding once, reading all of its
passages together.
[How judging works](https://hexdocs.pm/cite/how-judging-works.html) has
the details.

```mermaid
flowchart LR
    P["Policy"] --> R1
    S["Source"] --> R1
    R1["Round 1<br/>every question,<br/>every passage"] --> G["Gather<br/>fixed rules,<br/>no model"]
    G --> R2["Round 2<br/>one request<br/>per finding"]
    R2 --> Rep["Report<br/>findings and<br/>citations"]
```

Each finding has a **verdict**: `:holds`, `:review` (a person should
decide), or `:fails`. Each citation has its own verdict too. The model's
answers come back untouched: a citation's in `answer`, a finding's in
`checks` and `descriptors`. You decide what a level or a choice means.

To build a policy of your own, start with a tutorial:

- [Checking RAG answers against their sources](https://hexdocs.pm/cite/checking-rag-answers.html)
- [Filtering RAG retrieval results](https://hexdocs.pm/cite/filtering-rag-results.html)
- [Triaging logs](https://hexdocs.pm/cite/triaging-logs.html)
- [Checking support calls against procedure](https://hexdocs.pm/cite/checking-support-calls.html)
- [Finding sponsor segments](https://hexdocs.pm/cite/finding-sponsor-segments.html)

## What Cite does not do

- **It asks nothing beyond its two rounds.** One pass over every passage,
  then one judgment per finding.
- **It does not answer questions about the whole document.** Each request
  covers a batch of passages, or one finding.
- **It cites only passages you gave it.** Every finding is built from your
  source.

## Options

Four options tune a run:

- `threshold`, default `0.5`: how sure the first round must be before a
  passage joins a finding.
- `review_band`, default `{0.4, 0.6}`: answers between these two values go
  to `:review`.
- `window`, a positive integer, default `40`: how many passages go in each
  first-round request. At `1`, each request holds one passage.
- `concurrency`, a positive integer, default `4`: how many requests a round
  sends at once. Given the same replies, the report is the same at any
  setting. Set it within your provider's rate limits, or to `1` to send one
  request at a time.

Leave `threshold` alone at first. Lowering it does more than find more
passages: each one it adds is read together with the rest of its finding,
so it can change verdicts. It also makes the second round cost more.

## Errors

A mistake in a policy stops it from compiling. A mistake in the source or
in `Cite.judge/4`'s options raises `ArgumentError`, before any request is
sent. A provider's own options may fail later: Req checks some only when a
request goes out, so a misspelled one raises on the first request and ends
the run. A client that returns something outside its contract raises a
`RuntimeError` and ends the run: that's a bug in the client, not in your
arguments.

A failed request never counts as a "no". If the model or the network fails,
Cite reports an error and leaves the passages it covered without a verdict,
so you can tell "nothing found" from "not checked". Each error is a
`%Cite.Error{}` in the report's `errors`; `Cite.Error` lists the reasons.

## Testing without a key

The client is only a function, so a test can pass its own:

```elixir
client = fn %{"questions" => questions} ->
  answers = Map.new(questions, fn {key, _question} -> {key, %{"noul" => 0.9}} end)
  {:ok, %{answers: answers, usage: nil}}
end

%Cite.Report{findings: findings} = Cite.judge(client, source, Riddles)
```

Both rounds run for real; only the model is faked. This one answers "yes"
(0.9) to every question, so all three quick-start lines come back as
riddles.

Each answer must fit its question:

- yes or no: `%{"noul" => p}`
- a level: `%{"score" => s, "confidence" => p}`, where `s` is a number
  from 0 to the last level's index, and may fall between levels
- a choice: `%{"choice" => option_key, "confidence" => p}`

Any other shape fails the request.

To test the TypeSafe client itself, pass
`req_options: [plug: {Req.Test, name}]` to `Cite.client/2` and use
[`Req.Test`](https://hexdocs.pm/req/Req.Test.html).

## Providers

`Cite.judge/4` takes a client: a function from a request to
`{:ok, reply}` or `{:error, reason}`. `Cite.client/2` builds one from a
module implementing `Cite.Provider`. Build it once, where your credentials
live, and pass it in.

`Cite.Provider.TypeSafe` ships with Cite and calls TypeSafe's Jev. Its docs
list its options, what it retries, and why.

To write your own, implement `Cite.Provider`. The client receives
`%{"state" => map, "questions" => map}` and returns
`{:ok, %{answers: map, usage: usage | nil}}` (plus an optional `:model`
key) or `{:error, reason}`. A value in `"state"` may be a
`Cite.Wire.Object`, a JSON object that keeps its keys in order. Return
`{:error, :request_too_large}` when a request is too big. Cite then splits
a first-round request in half and retries.

## Stability

SemVer covers the **Core API**: `Cite.client/2`, `Cite.source/2`,
`Cite.judge/4`, the policy language, the structs you read (`Report`,
`Finding`, `Citation`, `Passage`, `Error`), and the client's request and
reply maps. The docs group modules by tier.

**Providers.** `Cite.Provider` may change in a minor release while it has
only one implementation; the changelog will say so.
`Cite.Provider.TypeSafe` is stable through its documented options.
`Cite.Wire.Object` is stable only through `Access` and `Jason.Encoder`.

**Internal.** Everything else carries no guarantee: the compiled policy
structs, the Spark extension, `Run`, `Screen`, `Gather`, `Gathered`,
`Judge`, `Placeholder`, `Wire`, and `Answer`. Their docs stay published
because they explain how Cite works.

The [roadmap](https://github.com/mdepolli/cite/blob/main/ROADMAP.md) lists
what is still being explored and what was ruled out.

## License

MIT. See the
[LICENSE](https://github.com/mdepolli/cite/blob/main/LICENSE) file.
