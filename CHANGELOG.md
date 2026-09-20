# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-09-20

### Added

- `Cite.select/5`: atomic scan over candidates, code-composed clusters, a
  compare round with a review band, and byte-exact spans out.
- `Cite.Candidate.from_segments/1`, `Cite.Question.noul/1`, `score/1`,
  `choice/1`, and `Cite.Cluster.new/1` as the typed inputs.
- `Cite.Result`, `Cite.Span`, and `Cite.Error` as the outputs, encodable
  with Jason or the built-in `JSON`; every failed judge call is an `Error`
  with its byte range and candidate ids.
- `Cite.Provider` behaviour and `Cite.Provider.TypeSafe`, a Req client for
  TypeSafe System One; `Cite.judge/2` builds the judge function.
- Windows over the provider's size cap are halved and retried
  (`:request_too_large`).
