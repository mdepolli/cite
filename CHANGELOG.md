# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Cite.select/5`: atomic scan over candidates in windows, code-composed
  clusters, a compare round gated by a review band, and byte-exact spans out.
  Options: `window_size`, `atomic_threshold`, `review_band`,
  `confidence_floor`, `state`.
- `Cite.Candidate.from_segments/1`, `Cite.Question.noul/1`, `score/1`,
  `choice/1`, and `Cite.Cluster.new/1` as the typed inputs. A cluster's
  `member_questions` names the Nouls that ground each member; `match: :all`
  or `:any` sets how its Nouls combine.
- `Cite.Result`, `Cite.Span`, and `Cite.Error` as the outputs, encodable
  with Jason or the built-in `JSON`. Spans carry the cluster's class, a label
  per Score (the level index) and Choice (the option) — `"uncertain"` below
  `confidence_floor` — and the raw answers. `Result` keeps the pre-threshold
  scan index, every rejected cluster with its answers, and token usage; every
  failed request is an `Error` with its byte range and candidate ids.
- `Cite.Provider` behaviour and `Cite.Provider.TypeSafe`, a Req client for
  TypeSafe System One; `Cite.new/2` builds the client function `select/5`
  takes. The TypeSafe client retries 429, 529, 500–504, and connection
  failures up to three times, honouring `Retry-After`, delays capped at 30
  seconds; timeouts are not retried.
- Windows over the provider's size cap (`{:error, :request_too_large}`) are
  halved and retried.
- Caller errors raise before the first request: candidates are checked
  against the source, atomics and options are validated, and what compose
  returns is checked. Anything the model or the network did is an `Error`
  in the result, never an exception.
