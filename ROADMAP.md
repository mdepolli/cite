# Roadmap

Where Cite is heading next. Plans change; the
[changelog](CHANGELOG.md) records what shipped.

- **Planned**: the direction is set, and the work is scheduled for 0.2.0.
- **Exploring**: the problem is real, but the fix waits on a benchmark. It
  ships only if the benchmark shows it helps, in 0.2.0 or later.
- **Not planned**: asked for or considered, and ruled out.

## Exploring

### A local provider, as its own package

Cite ships with one provider, `Cite.Provider.TypeSafe`, which calls
TypeSafe's Jev and needs an API key. A provider for the Laya decision model
would run on your own machine through Nx and Bumblebee. It will be a
separate package that implements `Cite.Provider`, so Cite itself never
depends on Nx, and its releases don't follow Nx's.

It waits on two fixes in the `laya` package. Its decision head uses GELU
where the original model uses ReLU. It also truncates long state silently,
so Cite never learns that a request was too large and never splits it.
Then the benchmarks must compare Laya's answers with Jev's before a
tutorial can recommend it.

### More than one case in a concern built from factors

A concern built from factors fills each role once, with its strongest match
in the whole source. So a transcript about two households never has the
second household judged. Roles can also mix cases: the strongest dependents
may come from one household and the strongest income from the other. A
check such as `same_household` then fails the finding, and Cite never
tries another combination. A caller can't recover the missed household
afterwards: it never reached round 2.

The aim is to judge each candidate case. One option is an anchored role:
each match for one role starts a candidate, the other roles are filled for
that candidate, and the concern's checks judge each candidate in its own
request. The benchmark must show that candidates are formed and judged as
a person would group them. Their cost in requests must stay in proportion
to the cases found. This changes what callers rely on: a concern could
report more than one finding.

Status: waiting for data. The transcripts measured so far are
inconclusive: none has a second household of the client's own to judge,
and their labels don't say which lines belong to which household. They
can't show whether a design groups cases as a person would.

### Context shared by every passage

A request has no place for context that every passage shares, such as the
question and documents a RAG answer is checked against. The caller copies
it into each passage's `meta` and shows it, so every passage sent carries
its own copy. At `window: 1` that is one copy per request. A larger window
would send one copy per passage in the same request.

The aim is to put context on the source, sent once per request beside the
window. The benchmark must show that checking many passages against one
copy holds up as well as checking them one at a time.

Status: measured, and it holds up only in part. On answers to questions,
one shared copy did as well as checking one at a time, with fewer input
tokens. On summaries it did worse: framing lines such as "Here is the
summary in 112 words:" passed as claims and were flagged, and borderline
sentences shifted both ways. The questions must stay as they are: pointing
them at the shared copy, or naming it by its path, lost precision
everywhere. Batching passages held up on both kinds when each passage
still carried its own copy of the context.

## Not planned

### Separate cases in a directly screened concern

A directly screened concern keeps every match in one finding, judged whole,
so a log with two unrelated kernel crashes reports one finding that cites
both. Splitting the matches into cases and judging each alone was measured
on video captions: it lost the weaker parts of real matches and raised
false alarms ([ADR 5](adr/0005-one-finding-per-directly-screened-concern.md)).
A caller who needs cases groups a finding's citations by the positions in
their `meta`, as the sponsor tutorial merges chunks into time ranges.

### A Python bridge

Local models will run through Nx and Bumblebee, in the same runtime as your
application. Cite will not call out to Python: that would add a second
runtime to install, deploy, and keep in step.
