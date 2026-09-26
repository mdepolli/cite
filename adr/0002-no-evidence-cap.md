# 2. No cap on a finding's evidence

Date: 2026-09-26

## Status

Accepted

## Context

v0.1.0's design capped a directly screened finding at `max_evidence` (20)
passages. The rest went to `Finding.over_cap`: reported, never judged. The
cap had two jobs: bound the round-2 request, and bound what an end user
reads.

The cap was set before anyone measured what one request can hold. On the
benchmark behind ADR 1, one request carried 79 passages without refusal or
slowdown, and no finding at the default threshold exceeded 11 passages.

## Decision

`max_evidence` and `over_cap` are removed before the first release. A
directly screened concern gathers every match, and round 2 judges them all
in one request (ADR 1).

## Consequences

- No passage that matched is left unjudged.
- The request bound is the provider's limit, not Cite's.
- Bounding what an end user reads is the caller's: the report carries every
  citation, and how many to show is presentation.
- The number of passages judged follows the threshold (ADR 4).
