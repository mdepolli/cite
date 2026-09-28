# 1. Judge a finding whole, in one request

Date: 2026-09-26

## Status

Accepted

## Context

Round 2 asks a confirm of every passage a finding gathered. A confirm could
read its passage alone, beside a window of the finding's passages, or beside
all of them.

Measured on an internal benchmark of conversation transcripts:

- Judged alone or in chunks of 1, 2, or 4, passages that carry a finding lost
  their reading. A line that refers back to an earlier turn ("I kind of
  resent it") scored 0.20 alone and held beside the line it refers to.
- Windows of 40 and 20 passages sat near the noise floor, and took 2 to 3.5
  times as long as one request.
- One request of 79 passages (51 KB) was answered in 0.4 s; latency was flat
  from 1 to 79 passages. The provider documents no size limit, and requests
  of 189 KB pass.

## Decision

A finding is judged whole: one request holds every passage it gathered,
every confirm, and the descriptors. Round 2 is never split into windows, and
there is no lead request of the strongest passages. Cite sets no size limit
of its own. A request the provider refuses as too large is that finding's
error; how to meet a refusal will be decided from the first one seen.

## Consequences

- A confirm judges a passage's part in the whole matter, so a finding's
  citations are judged as a set. Callers should present them together.
- Who is gathered changes what every confirm scores; round-1 noise reaches
  round-2 verdicts.
- Measured on conversations, where lines lean on turns far away. A source of
  self-contained passages may gain nothing from siblings; that is untested.
- A very large finding is one large request, not several. Cost grows in
  bytes, not requests.
