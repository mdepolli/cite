# 4. The threshold stays at 0.5

Date: 2026-09-26

## Status

Accepted

## Context

With no cap (ADR 2), a looser detect gathers a larger matter, and a finding's
confirms read all of it (ADR 1). That suggested lowering the default
threshold. `threshold`'s doc said it "sets recall only".

The benchmark behind ADR 1 ran the detect at 0.5, 0.2, 0.1, and 0.05,
filters and factors held at 0.5, each configuration twice, scored against a
human reviewer's verdicts and per-line labels:

- Inside findings that exist at 0.5, a looser detect cited more of the
  labelled lines and lost none the reviewer kept.
- Elsewhere it invented findings the reviewer had rejected, in concerns with
  no match at 0.5, and review load grew five- to tenfold.
- A variant loosening only concerns that already match at 0.5 removed the
  invented findings but still held lines the reviewer rejected.

## Decision

The default stays at 0.5, one bar for filters, factors, and detects. The
doc no longer says the threshold sets recall only.

## Consequences

- The threshold's doc says it decides which passages are screened in, that a
  finding's confirms read every passage gathered with it, and that below
  0.5, measured on transcripts, it invents findings and multiplies review
  load.
- A caller can still lower it; nothing guards against that.
- A per-concern or anchored gather stays an open question for a benchmark
  with more kinds of source.
