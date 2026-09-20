# Select and judge

What happens between `Cite.select/5` and the spans it returns, with the
actual requests and replies at each step. The example is the Mad Tea-Party.

```elixir
candidates =
  Cite.Candidate.from_segments([
    %{text: "Why is a raven like a writing-desk?", meta: %{speaker: "Hatter"}},
    %{text: "Take some more tea.", meta: %{speaker: "March Hare"}}
  ])

source = Enum.map_join(candidates, " ", & &1.text)
# "Why is a raven like a writing-desk? Take some more tea."
# C000 is bytes 0..35, C001 is bytes 36..55
```

## 1. Scan

Every atomic is asked of every candidate, `window_size` candidates per
request. With one atomic, `riddle`, and both candidates in one window, the
client receives this:

```json
{
  "state": {
    "candidates": {
      "C000": {"id": "C000", "speaker": "Hatter", "text": "Why is a raven like a writing-desk?"},
      "C001": {"id": "C001", "speaker": "March Hare", "text": "Take some more tea."}
    }
  },
  "questions": {
    "C000:riddle": {
      "type": "noul",
      "instructions": {
        "question": "Does `candidates.C000.text` pose a riddle?",
        "inspect": "`candidates.C000.text`"
      },
      "criteria": {
        "true": {"what": "A question asked to be puzzled over, whether or not it has an answer."},
        "false": {"what": "A plain question, a statement, or a remark."}
      }
    },
    "C001:riddle": { "..." : "same question, addressed to C001" }
  }
}
```

Three things to notice. The window sits under `"candidates"`, each
candidate as its `meta` plus `"id"` and `"text"`. Question keys are
`"#{candidate_id}:#{atomic_name}"`. And every question in the request sees
the whole state — the request is the boundary of what the model can read,
so a question's `inspect` path tells it where to look.

The client answers:

```elixir
{:ok, %{answers: %{"C000:riddle" => %{"noul" => 0.94}, "C001:riddle" => %{"noul" => 0.03}},
        usage: %{input_tokens: 412, output_tokens: 0}}}
```

Answers fold into the index, `%{candidate_id => %{atomic => probability}}`,
and `atomic_threshold` (default 0.5) drops what falls at or below it:

```elixir
%{"C000" => %{"riddle" => 0.94}, "C001" => %{}}
```

Every candidate keeps a row, even an empty one. A candidate whose window
*failed* has no row at all — its error is in `Result.errors` — so compose
looks candidates up with `Map.get/2`.

A request the provider refuses as too large comes back as
`{:error, :request_too_large}`; the window is split in half and both halves
are sent. Only a single candidate that still exceeds the cap becomes an
error.

## 2. Compose

Your function receives the thresholded index and the candidates, and
returns clusters — the candidates that together evidence one finding, with
the questions that will verify it. It is pure: no client, no I/O. Here, one
cluster per riddle, verified by one Noul and labelled by a Score and a
Choice:

```elixir
fn index, candidates ->
  for c <- candidates, index[c.id]["riddle"] do
    Cite.Cluster.new(
      id: "riddle:#{c.id}",
      class: "riddle",
      members: [c],
      state: %{"line" => c},
      questions: %{
        "unanswered" => unanswered,
        "nonsense" => nonsense,
        "speaker" => speaker
      }
    )
  end
end
```

`Cite.select/5` checks what came back before spending anything: a list of
`%Cite.Cluster{}`, unique ids, every member one of the candidates.

## 3. Compare

Each cluster gets one request on its own small state. Candidates placed in
`state` are wired the same way the scan wires them:

```json
{
  "state": {
    "line": {"id": "C000", "speaker": "Hatter", "text": "Why is a raven like a writing-desk?"}
  },
  "questions": {
    "unanswered": {
      "type": "noul",
      "instructions": {
        "question": "Is the riddle in `line.text` left without an answer in the line itself?",
        "inspect": "`line.text`"
      },
      "criteria": {
        "true": {
          "what": "The line asks and does not answer.",
          "not_for": "A rhetorical question the speaker answers at once.",
          "examples": ["Why is a raven like a writing-desk?"]
        },
        "false": {"what": "The line supplies or hints at the answer."}
      }
    },
    "nonsense": {
      "type": "score",
      "instructions": {"question": "How much sense does `line.text` make?", "inspect": "`line.text`"},
      "criteria": ["Perfectly sensible.", "Odd, but it could be answered.", "Pure nonsense."]
    },
    "speaker": {
      "type": "choice",
      "instructions": {"question": "Who is most likely speaking in `line.text`?", "inspect": "`line.text`"},
      "criteria": {"hatter": "The Hatter", "hare": "The March Hare", "dormouse": "The Dormouse", "alice": "Alice"}
    }
  }
}
```

And a reply:

```elixir
{:ok, %{answers: %{
  "unanswered" => %{"noul" => 0.88},
  "nonsense" => %{"score" => 1.3, "confidence" => 0.71, "legend" => [...], "probabilities" => [...]},
  "speaker" => %{"choice" => "hatter", "confidence" => 0.92, "probabilities" => %{...}}
}, usage: %{input_tokens: 388, output_tokens: 0}}}
```

Only the Nouls gate. With `review_band` `{0.4, 0.6}` and `match: :all`
(the default): any Noul at or below 0.4 rejects the cluster; every Noul at
or above 0.6 accepts it; anything else sends it out for review. With
`match: :any`, one Noul clearing 0.6 accepts and one above 0.4 reviews. A
cluster with no Nouls has nothing to gate and is accepted; a cluster with
no questions at all is accepted without a request.

A reply that skips a question is not a verdict on it. The model promises one
answer per question, so the request becomes a `Cite.Error` with reason
`{:missing_answers, keys}` and nothing from it is read — a scan window
contributes no index rows, a cluster is neither accepted nor rejected.

`member_questions` narrows which members are grounded: name the Noul(s)
that vouch for a member and it is emitted only when one of them is above
`low`. Members not named are always emitted. A cluster that passes the gate
but grounds nobody is rejected — there is nothing to cite.

## 4. Emit

Every grounded member becomes a `Cite.Span`: the exact bytes, copied from
`source` at the candidate's offsets.

```elixir
%Cite.Span{
  text: "Why is a raven like a writing-desk?",
  byte_start: 0,
  byte_end: 35,
  candidate_id: "C000",
  class: "riddle",
  attributes: %{
    "cluster_id" => "riddle:C000",
    "review" => false,
    "nonsense" => 1,
    "speaker" => "hatter",
    "compare" => %{"unanswered" => %{"noul" => 0.88}, "nonsense" => %{...}, "speaker" => %{...}}
  }
}
```

The Score labels as `round(score)` — the level index, `1` here for "Odd, but
it could be answered." — and the Choice as its option. Either becomes
`"uncertain"` when the answer's `confidence` is below `confidence_floor`
(default 0.5). Cite knows no question names; the raw answers travel under
`"compare"` so your code can relabel without another request.

## What comes back

```elixir
%Cite.Result{
  spans: [%Cite.Span{...}],
  errors: [],
  usage: %{input_tokens: 800, output_tokens: 0},
  models: ["jev-1.13.0"],
  scan: %{"C000" => %{"riddle" => 0.94}, "C001" => %{"riddle" => 0.03}},
  rejected: %{}
}
```

`scan` is the index *before* thresholding, `rejected` every cluster that
reached compare and failed its gate, with its answers. `errors` lists scan
errors in window order, then compare errors in cluster order, each with the
byte range and candidate ids it covered. A run is diagnosable without another
request.
