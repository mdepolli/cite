# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `concurrency` on `Cite.judge/4`: the most requests in flight at once
  within a round, 4 by default. The report is the same at any setting; set
  `concurrency: 1` to send one request at a time, as 0.1 did.
- `Cite.ClientError`, raised mid-run when a client returns something
  outside its contract.

### Changed

- A client that returns something outside its contract raises
  `Cite.ClientError` instead of `ArgumentError`, which now means only a bad
  argument to `Cite.judge/4`, raised before any request.
- The client runs in a task process, at every `concurrency`. Logger
  metadata and process level carry over, and so does `$callers`, which
  Mox and `Req.Test` rely on; the rest of the caller's process dictionary,
  OpenTelemetry context included, does not.
- A crash in a process the client links to now exits `Cite.judge/4` with
  the same reason, even in a caller that traps exits. Before, such a
  caller, a GenServer for instance, received an `:EXIT` message and the
  run carried on.
- At `concurrency` above 1, a raise mid-run comes once the requests before
  it have answered. Requests started meanwhile are stopped, but the
  provider may already have received, and billed, them.
- `Cite.Provider.TypeSafe` waits for a pooled connection with no time
  limit, instead of raising after 5 seconds. Timeouts in the app's default
  `finch:` list, in `Req.default_options/0`, no longer apply to TypeSafe:
  Req reads them over the adapter's own. One in `req_options`'
  `finch: [...]` still does.
- `Cite.Provider.TypeSafe` refuses, when the client is built rather than on
  the first request: `:connect_options`; `finch:` as a bare pool name;
  `finch:` pool options beside a pool `name:`; and a default `:retry_delay`
  without a `:retry` in `req_options`. These hold in `req_options` and in
  the app's `Req.default_options/0`, whose `finch:` list still applies,
  beneath the client's own. Set Finch options under `finch: [...]` instead
  of `:connect_options`.
- The RAG grounding tutorial runs at the default window: screening an
  answer's sentences together costs no more and makes no more mistakes
  than one at a time.

### Fixed

- `Cite.source/2` raises on shown meta that holds a key as both an atom
  and a string, such as `%{k: 1, "k" => 2}`, and on a `show` that names
  one key both ways. On the wire they were one key, and which value the
  model saw depended on map order.
- `Cite.client/2` raises `ArgumentError` on an atom that is not a
  provider module, instead of `UndefinedFunctionError`.

## [0.1.1] - 2026-09-28

### Added

- Tutorial: Checking RAG answers against their sources. It finds the
  sentences of a generated answer that its retrieved documents contradict
  or never state, with a filter for sentences that assert nothing.
- Tutorial: Filtering RAG retrieval results. It keeps the retrieved
  passages that answer a query, judging each query's candidates together.
- A [roadmap](https://github.com/mdepolli/cite/blob/main/ROADMAP.md) for
  0.2.0, marking each item planned, exploring, or not planned.
- A logo, shown in the docs sidebar, as the favicon, and beside the README
  heading.

### Changed

- The guides say what one round-1 request holds, and that shown meta is
  the only context a passage carries besides its text: a value every
  passage shares, such as the question they are judged against, goes on
  each passage. The `window` docs say it takes any positive integer,
  including 1.
- Writing policies defines `not_for` against its own block's `what`, so it
  can go in a `no` block as well as a `yes`.
- Each tutorial opens by saying what you write and build, and what Cite
  does in between.

### Security

- Mint, the HTTP client under Req, has three advisories fixed in 1.11.0
  (EEF-CVE-2026-91043, EEF-CVE-2026-92103, EEF-CVE-2026-94194). Cite's own
  lockfile now pins 1.11.0. Hex packages do not ship a lockfile, so run
  `mix deps.update mint` in your project.

## [0.1.0] - 2026-09-27

### Added

- `use Cite.Policy`: a policy declared once in a module, built on Spark.
  Filters, concerns (screened directly with a detect and an optional
  confirm, or built from factors with roles and checks), factors, and Score
  or Choice descriptors. A passage is evidence for every concern it matches.
  Questions name what they read by placeholder (`{passage}`, `{household}`)
  and Cite replaces each with a path in the request. Any question may add
  a one-line `focus`. Every mistake in a policy is a compile error.
- A DSL reference in `Cite.Policy`'s docs, generated from the DSL by Spark.
- `Cite.source/2`: the caller's passages, kept byte for byte, with `as:` for
  the word they sit under and `show:` for the meta the model sees.
- `Cite.judge/4`: two fixed rounds. A screen of every passage for every
  detect in windows, fixed rules that gather matches into findings, and
  one judgment per finding on all of its evidence, gated by a review band.
  Options: `threshold`, `review_band`, `window`. A client, source, policy,
  or options of the wrong kind raise `ArgumentError`.
- Replies are checked before they count: a reply that skips a question or
  answers out of range makes its whole request an error, never a verdict.
  Errors are reported beside the findings, one per failed request.
- `Cite.Report`, `Cite.Finding`, `Cite.Citation`, `Cite.Passage`, and
  `Cite.Error` as the outputs, encodable with Jason. A finding carries its
  verdict, the raw answers to its checks and descriptors, the passages it
  cites and those its confirm dropped; the report keeps every round-1 score,
  token usage, and the model ids that answered.
- `Cite.Provider` behaviour and `Cite.Provider.TypeSafe`, a Req client for
  TypeSafe System One; `Cite.client/2` builds the client function
  `judge/4` takes. A request's `"state"` may hold `Cite.Wire.Object`
  values, JSON objects that keep their key order. The TypeSafe client takes
  `api_key`, `model`, `base_url`, `max_retry_delay`, and `req_options`. It
  retries 429, 529, 500–504, and connection failures up to three times,
  honouring `Retry-After`, with delays capped at 30 seconds; timeouts are
  not retried.
- Round-1 windows over the provider's size cap (`{:error,
  :request_too_large}`) are halved and retried; only a lone passage still
  over the cap becomes an error. A round-2 request refused as too large is
  that finding's error.
- Guides: Writing policies, and How judging works. Tutorials, each building
  a policy from scratch: Triaging logs, Finding sponsor segments,
  Labelling allergens in recipes, and Checking support calls against
  procedure.
- Stability tiers, named in the README and grouping the docs: Core API
  (the SemVer contract), Providers, and Internal.
- Requires Elixir `~> 1.18`.

[Unreleased]: https://github.com/mdepolli/cite/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/mdepolli/cite/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/mdepolli/cite/releases/tag/v0.1.0
