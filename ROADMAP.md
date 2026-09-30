# Roadmap

Where Cite is heading next. Plans change; the
[changelog](CHANGELOG.md) records what shipped.

- **Planned**: the direction is set, and the work is scheduled for 0.2.0.
- **Exploring**: the problem is real, but the fix waits on a benchmark. It
  ships only if the benchmark shows it helps, in 0.2.0 or later.
- **Not planned**: asked for or considered, and ruled out.

## Planned for 0.2.0

### Concurrent requests

Cite sends every request one after another: each round-1 window, then each
finding. A run's latency grows with the length of the source and the number
of findings.

0.2.0 sends each round's requests concurrently, with a `:concurrency`
option on `Cite.judge/4`. Results keep their order, so errors and usage
stay in window and finding order. The rounds themselves stay in sequence:
round 2 needs round 1's scores.

### A local provider

Cite ships with one provider, `Cite.Provider.TypeSafe`, which calls
TypeSafe's Jev and needs an API key. 0.2.0 adds `Cite.Provider.Laya`, which
runs the Laya decision model on your own machine through Bumblebee. It is an
optional dependency: callers who use TypeSafe do not pull in Nx.

It waits on two fixes in the `laya` package. Its decision head uses GELU
where the original model uses ReLU. And it truncates long state silently,
so Cite cannot tell that a request was too large and split it.

## Exploring

### Separate cases in a directly screened concern

A directly screened concern gathers every match into one finding, judged in
one request. A log with two unrelated kernel crashes reports one finding
that cites both, and each crash's lines are judged beside the other's.

A caller can already split that finding into cases: every citation carries
its passage, `meta` included, so matches can be grouped by position, as the
sponsor tutorial merges chunks into time ranges. What a caller can't change
is that the cases were judged together. Judging a finding whole helps on
conversations, where a line that refers back to another holds beside it and
fails alone ([ADR 1](adr/0001-judge-a-finding-whole.md)). On
self-contained passages, such as log lines, the gain is untested, and an
unrelated case beside a passage may hurt it instead.

The first step is to measure that. If judging unrelated cases together does
no harm, the answer is a documented pattern for grouping citations, not a
new mechanism. If it does harm, Cite needs a rule that splits matches into
cases before round 2: by distance in the source, by a question that asks
whether two matches belong together, or another rule. The benchmark must
show the rule groups matches as a person would, and keeps what judging a
finding whole gains. A split would let a concern report more than one
finding, so code that expects at most one per concern would need to
change.

### More than one case in a concern built from factors

A concern built from factors fills each role once, with its strongest match
in the whole source. So a transcript about two households never has the
second household judged. Roles can also mix cases: the strongest dependents
may come from one household and the strongest income from the other. A
check such as `same_household` then fails the finding, and Cite never
tries another combination. Unlike the directly screened case, a caller
can't recover the missed household afterwards: it never reached round 2.

The aim is to judge each candidate case. One direction is an anchored
role: each match for one role starts a candidate, the other roles are
filled for that candidate, and the concern's checks judge each candidate in
its own request. The benchmark must show candidates are formed and judged
as a person would group them, at a cost in requests that stays in
proportion to the cases found. This changes what callers rely on: a
concern could report more than one finding.

### Context shared by every passage

A request has no place for context that every passage shares, such as the
question and documents a RAG answer is checked against. The caller copies
it into each passage's `meta` and shows it, so every passage sent carries
its own copy. At `window: 1` that is one copy per request. A larger window
would send one copy per passage in the same request.

The aim is to put context on the source, sent once per request beside the
window. The benchmark must show that checking many passages against one
copy holds up as well as checking them one at a time.

## Not planned

### A Python bridge

Local models will run through Nx and Bumblebee, in the same runtime as your
application. Cite will not call out to Python: that would add a second
runtime to install, deploy, and keep in step.
