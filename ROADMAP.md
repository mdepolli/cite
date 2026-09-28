# Roadmap

Where Cite is heading after 0.1.0. Plans change; the
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

### More than one finding per concern

A directly screened concern gathers every match into one finding. A concern
built from factors fills each role once, with its strongest match. So a log
with two unrelated kernel crashes reports one finding that cites both, and
a transcript about two households never has the second household judged.
Cite answers "is this here, and where?", not "how many separate cases are
there?".

The aim is to let a concern report separate findings for separate cases.
How to tell cases apart is open: by distance in the source, by a question
that asks whether two matches belong together, or another rule. The
benchmark must show a rule groups matches as a person would. The rule must
also keep what judging a finding whole gains: a line that refers back to
another holds beside it and fails alone
([ADR 1](adr/0001-judge-a-finding-whole.md)).

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
