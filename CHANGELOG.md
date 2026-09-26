# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `use Cite.Policy`: a policy declared once in a module, built on Spark.
  Filters, concerns (screened directly with a detect and an optional
  confirm, or built from factors with roles and checks), factors, and Score or
  Choice descriptors. A passage is evidence for every concern it matches. Questions
  name what they read by placeholder (`{passage}`, `{household}`) and Cite
  writes the path. Every mistake in a policy is a compile error.
- A DSL reference in `Cite.Policy`'s docs, generated from the DSL by Spark.
- `Cite.source/2`: the caller's passages, kept byte for byte, with `as:` for
  the word they sit under and `show:` for the meta the model sees.
- `Cite.judge/4`: two fixed rounds. A screen of every passage for every
  detect in windows, fixed rules that gather matches into findings, and
  one judgment per finding on all of its evidence, gated by a review band.
  Options: `threshold`, `review_band`, `window`.
- `Cite.Report`, `Cite.Finding`, `Cite.Citation`, `Cite.Passage`, and
  `Cite.Error` as the outputs, encodable with Jason. A finding carries its
  verdict, the raw answers to its checks and descriptors, the passages it
  cites and those its confirm dropped; the report
  keeps every round-1 score, token usage, and the model ids that answered.
- `Cite.Provider` behaviour and `Cite.Provider.TypeSafe`, a Req client for
  TypeSafe System One; `Cite.client/2` builds the client function
  `judge/4` takes. The TypeSafe client retries 429, 529, 500–504, and
  connection failures up to three times, honouring `Retry-After`, delays
  capped at 30 seconds; timeouts are not retried.
- Round-1 windows over the provider's size cap (`{:error,
  :request_too_large}`) are halved and retried.
- Requires Elixir `~> 1.18`.
