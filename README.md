# Cite

Candidates in, grounded citations out.

Code proposes candidates — utterances, rows, sentences, anything it can
enumerate. A System One judge answers narrow typed questions about them:
Nouls (a probability), Scores (a level), Choices (an option). Cite copies the
evidence byte-exact from the source. Nothing is generated; nothing is aligned.

## How a run goes

1. **Scan.** Every atomic question is asked of every candidate, in windows.
   The answers become an index: `%{candidate_id => %{atomic => noul}}`.
2. **Compose.** Your code turns the index into clusters — the candidates that
   together evidence one finding, with the questions that will verify it.
3. **Compare.** Each cluster is judged on its own small state. Nouls gate it
   through a review band; Scores and Choices label it.
4. **Emit.** Every grounded member becomes a `Cite.Span`: the exact bytes,
   their offsets, the cluster's class, and the labelled answers.

```elixir
judge = Cite.judge(api_key: System.fetch_env!("JEV_API_KEY"))

candidates =
  Cite.Candidate.from_segments([
    %{text: "We've got four kids at home.", meta: %{speaker: "B"}},
    %{text: "I make about 180k a year.", meta: %{speaker: "B"}}
  ])

source = Enum.map_join(candidates, " ", & &1.text)

dependents = fn %Cite.Candidate{id: id} ->
  Cite.Question.noul(
    question: "Does `candidates.#{id}.text` mention children or dependents?",
    inspect: "`candidates.#{id}.text`",
    true: "States children, dependents, or household size.",
    false: "No dependents mentioned."
  )
end

spec = %{
  atomics: [%{name: "dependents", question: dependents}],
  compose: fn index, candidates ->
    for {id, %{"dependents" => _}} <- index, member = Enum.find(candidates, &(&1.id == id)) do
      Cite.Cluster.new(
        id: "dependents:#{id}",
        class: "resilience",
        members: [member],
        state: %{"line" => member},
        questions: %{
          "fits" =>
            Cite.Question.noul(
              question: "Does `line.text` say the speaker supports dependents?",
              inspect: "`line.text`",
              true: "The speaker's own children or dependents.",
              false: "Someone else's, or hypothetical."
            )
        }
      )
    end
  end
}

%Cite.Result{spans: spans} = Cite.select(judge, source, candidates, spec)
```

Each span carries `text`, `byte_start`, `byte_end`, `candidate_id`, `class`,
and `attributes` (`"cluster_id"`, `"review"`, the raw `"compare"` answers,
and one label per Score or Choice). `Cite.Result` also holds the scan index,
every rejected cluster with its answers, token usage, and one `Cite.Error`
per failed judge call — a run is diagnosable without another request.

See the `Cite` module docs for the judge and spec contracts and the options
(`window_size`, `atomic_threshold`, `review_band`, `confidence_floor`).

## Providers

`Cite.judge/1` builds a judge for TypeSafe System One. Any module
implementing `Cite.Provider` works through `Cite.judge/2`, and any 1-arity
function of the right shape works directly, which is how the tests run
without a key.

Scan windows are judged one after another; a long document is one request
per window, each up to 120 seconds. Concurrency is not yet an option.

## Installation

```elixir
def deps do
  [
    {:cite, "~> 0.1.0"}
  ]
end
```

## License

MIT — see [LICENSE](https://github.com/mdepolli/cite/blob/main/LICENSE).
