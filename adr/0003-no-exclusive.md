# 3. No `exclusive`

Date: 2026-09-26

## Status

Accepted

## Context

A policy could set `exclusive true`: a passage matching several directly
screened concerns stayed only with the one whose round-1 score was highest,
and the choice was final, even if that concern's confirm later dropped it.

Round-1 scores come from differently worded questions, which carry no
calibration promise between them. On the benchmark behind ADR 1, the option
decided one line in five transcripts at the default threshold, a line two of
the policy's concerns both claimed. With a looser detect, a third to a half
of matching lines matched several concerns, and the highest score compared
noise.

## Decision

`exclusive` is removed. A passage is evidence for every directly screened
concern it matches, and each concern's confirm judges it.

## Consequences

- Deciding between overlapping concerns is the policy's semantics: a
  `not_for` keeps one concern off the other's ground. Or the caller decides
  when presenting. Comparing two confirms is no better calibrated than
  comparing round-1 scores.
- A passage two concerns claim is cited by both, and sits in both concerns'
  round-2 requests.
- One option fewer in the policy language.
