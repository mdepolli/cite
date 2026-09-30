# 5. One finding per directly screened concern

Date: 2026-09-29

## Status

Accepted

## Context

A directly screened concern gathers every match into one finding, judged
whole ([ADR 1](0001-judge-a-finding-whole.md)). When a source holds two
unrelated cases, such as two sponsor reads in one video, both are judged in
the same request. Cite could instead split the matches into cases before
round 2 and judge each alone. ADR 1 measured the gain from judging together
on conversations, and left sources of self-contained passages untested.

Measured on an internal benchmark of video captions: 14 videos, 6 with two
or more sponsor reads and 8 where a real read shared a finding with false
alarms. Each finding was judged whole and then case by case, with cases
taken from the labels, 3 times each, on one model version.

- Chunks of a real read: 13 of 59 moved beyond run-to-run noise, 11 of them
  down when judged alone, by up to 0.42 (0.61 to 0.19, holds to drop).
  Chunks that carry only part of a read leaned on the rest of it.
- False alarms: 9 of 13 moved, 7 of them up when judged alone, by up to
  0.22. Beside a real read, a passage that is not one scores lower.

## Decision

A directly screened concern reports one finding, judged whole, however many
cases its matches span. Cite has no rule that splits matches into cases. A
caller who needs cases groups a finding's citations afterwards, by the
positions it keeps in `meta`.

## Consequences

- A finding can cite unrelated cases. Its citations were judged as a set;
  group them for display, after judging.
- The cases above came from labels Cite cannot see. A rule applied at
  runtime could only group worse.
- Caption chunks are fragments of speech. Self-contained passages such as
  log lines remain untested, and follow the same rule until a benchmark
  says otherwise.
- A concern built from factors is a separate question: there, a second case
  is never judged at all.
