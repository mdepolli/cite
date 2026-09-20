# Writing questions

Atomics and compose are where your judgment goes in. The model reads
literally, so the work is in the wording. These are the rules that held up.

## One proposition per question

A Noul is a yes/no with a probability. Ask one thing:

```elixir
Cite.Question.noul(
  question: "Does `candidates.#{id}.text` pose a riddle?",
  inspect: "`candidates.#{id}.text`",
  true: "A question asked to be puzzled over, whether or not it has an answer.",
  false: "A plain question, a statement, or a remark."
)
```

"Does it pose a riddle *and* is it unanswered" is two questions; the model
will answer whichever it weighs more. Ask the second in compare, on the
cluster's own state, where it can be independent.

## Put the path in the question

The `inspect` path names what the model should read; the question text
should name it too, in backticks, so the two agree:

```
question: "Does `candidates.#{id}.text` pose a riddle?"
inspect:  "`candidates.#{id}.text`"
```

In the scan the window is under `"candidates"`, so a scan question addresses
`` `candidates.#{id}.text` ``. In compare the state is the cluster's own —
`%{"line" => c}` becomes `` `line.text` ``, `%{"lines" => [c0, c5]}` becomes
`` `lines.C000.text` `` and `` `lines.C005.text` `` — a list of candidates is
wired as an object keyed by id, in order. Whatever `meta` a candidate carries rides
along: `` `line.speaker` `` works if `meta` had `:speaker`.

A path that points nowhere is not an error the model reports; it answers
against nothing and the Noul comes back near zero. `Cite.select/5` cannot
check this for you, because it does not know which keys your criteria
mention. A test can: run the spec through `Cite.select/5` with a stub client
that asserts every `inspect` path resolves inside its request's `"state"`.

## Boundary cases go in `not_for`

The first wording of a question is the half of the instruction you thought
of. The wrong answers you meet afterwards are the other half. Put them in
the criteria, as paraphrases, not as fixture lines:

```elixir
Cite.Question.noul(
  question: "Is the riddle in `line.text` left without an answer in the line itself?",
  inspect: "`line.text`",
  true: %{
    what: "The line asks and does not answer.",
    not_for: "A rhetorical question the speaker answers at once.",
    examples: ["Why is a raven like a writing-desk?"]
  },
  false: "The line supplies or hints at the answer."
)
```

A bare string is `%{what: string}`. `not_for` names what a reading of
`what` might wrongly include; `examples` are short phrasings that should
qualify. Both sides can carry them. The question and the criteria must
agree — when they disagree, the model answers the question and ignores the
criteria.

## Scores are levels, Choices are options

A Score places the state on an ordered scale and returns a position:

```elixir
Cite.Question.score(
  question: "How much sense does `line.text` make?",
  inspect: "`line.text`",
  criteria: ["Perfectly sensible.", "Odd, but it could be answered.", "Pure nonsense."]
)
```

The answer's `score` runs `0..N-1`; Cite labels the span with `round(score)`,
the level index. Two to ten levels. Make every level reachable from what the
state can show — a level no line could ever earn flattens the model's
confidence on all the others.

A Choice picks one option and says how sure it is:

```elixir
Cite.Question.choice(
  question: "Who is most likely speaking in `line.text`?",
  inspect: "`line.text`",
  criteria: %{"hatter" => "The Hatter", "hare" => "The March Hare", "dormouse" => "The Dormouse", "alice" => "Alice"}
)
```

The option key is what lands in the span's attributes. Keep option sets
small; past a couple of dozen, split the question.

Both label as `"uncertain"` when `confidence` is under `confidence_floor`.
Neither gates a cluster; only Nouls do.

## Compose decides what a finding is

The index says which lines scored on which atomics. Compose says which lines,
together, are one thing worth citing. Three shapes cover most cases.

**One cluster per hit.** The simplest: every scoring line is its own finding.

```elixir
for c <- candidates, index[c.id]["riddle"] do
  Cite.Cluster.new(id: c.id, class: "riddle", members: [c], state: %{"line" => c}, questions: %{"unanswered" => unanswered})
end
```

**One cluster per atomic, across the document.** When the finding is "this
document has riddles in it", not "this line is a riddle", every hit is a
member of one cluster and each member gets its own verifier:

```elixir
hits = for c <- candidates, index[c.id]["riddle"], do: c

[
  Cite.Cluster.new(
    id: "riddles",
    class: "riddle",
    members: hits,
    state: %{"lines" => hits},
    questions: Map.new(hits, &{"unanswered:#{&1.id}", unanswered_for(&1.id)}),
    member_questions: Map.new(hits, &{&1.id, ["unanswered:#{&1.id}"]}),
    match: :any
  )
]
```

`match: :any` accepts the cluster if any line's verifier clears; each line is
then grounded only if its own did. Every member of a cluster shares one
request, so the model sees them together — that is what you want when the
members are related, and what you must avoid when a judgment has to be
independent. Pass the members as a list, not a map: past 32 entries a map
reaches the model in hash order, and order is context.

**A cluster built from several atomics.** When one finding needs evidence of
two kinds — a question and its answer, say — pick the best line for each
role and put both in the state under role names:

```elixir
state = %{"riddle" => riddle_line, "answer" => answer_line}
# questions address `riddle.text` and `answer.text`
```

If the best line for both roles is the same line, it is the strongest
evidence you have, not the weakest: one member, both roles pointing at it,
and skip the cross-check that would compare it with itself.

## Pin the wording

Once the questions work, they are part of the benchmark. Keep them in one
module, under test, with the request paths checked. A model's reading of the
same wording shifts between versions — the TypeSafe provider pins its model
for that reason — so a change of model is a change of questions until you
have measured otherwise.
