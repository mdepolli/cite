# 6. A hand-written round scheduler

Date: 2026-09-30

## Status

Accepted

## Context

A round sends its requests up to `concurrency` at once and returns the
replies in order. `Task.async_stream/3` does that in a few lines.

When a request fails, `Cite.judge/4` promises that no further request
starts, since every request sent is billed. A crash in a process the client
links to reaches a caller that traps exits as an exit with the crash's
reason.

## Decision

`Cite.Round` schedules a round itself. Each request runs in `Task.async/1`,
and the caller reads every reply and every `:DOWN` as a message.

Everything else is as the stream had it: replies in item order, the first
failure in item order, a failure delivered once the requests before it have
answered, and the requests after it stopped.

## Rationale

- `Task.async/1` monitors the task and sends it its job from the caller, so
  the monitor lands first and a task that dies at once reports its real
  reason.
- A failure of any kind, a linked crash included, is seen in the caller
  before the next request starts, so none starts after it.

The first two designs used `Task.async_stream/3`, and both fell short.

**An ordered stream.** Requests kept starting after a failure. An ordered
stream delivers a failure only once the requests before it have answered,
and starts new ones while it waits. With 40 one-passage windows at
`concurrency: 4`, a slow first request and a second that failed at once,
all 40 were sent before the raise.

**An ordered stream behind a flag.** A failing task set an `:atomics` flag
before it replied, and a `Stream.take_while/2` in front of the stream
stopped pulling items. That closed most of the gap. A task killed from
outside, by a crash in a process the client linked to, never reaches the
code that sets the flag. A caller that traps exits kept starting requests
until that exit's turn came.

**Any stream can report the wrong exit reason.** A test of that linked
crash failed about once in 5,000 runs: `judge/4` exited with `:noproc`
instead of the crash's reason. The cause is in `Task.Supervised`. The
stream monitors a task from one process and sends the task its job from
another, and signals from two senders have no order. A task that dies
within microseconds of starting can be dead before the monitor lands, and
the `:DOWN` then says `:noproc`.

Reproduced on `Task.async_stream/3` alone, without Cite, on Elixir 1.20.4
and OTP 29.1.1: 8 times in 16 million runs across 8 loaded BEAMs, and 0 in
2.2 million unloaded. Cite cannot recover the real reason from the stream.

**An unordered stream whose reducer sets the flag.** It stops new requests
after a linked crash in about 40 lines, but it still goes through
`Task.Supervised` and keeps the `:noproc` race.

## Consequences

- Cite owns what the stream did for free. `Cite.Round` unlinks each
  finished task and drops its `:EXIT`, so a caller that traps exits keeps a
  clean mailbox, and it kills the tasks still running on a failure. The
  module is about 190 lines where the stream took about 30.
- Nothing in the caller may raise between the first task and the kill of
  the rest, or a task outlives the round. No `try/after` enforces it; a
  step added there, such as a deadline, must keep it true.
- Each receive matches any of the round's refs, so it scans the caller's
  whole mailbox. That costs about three scans per request more than the
  stream's. It only counts for a caller with a backlog, such as a busy
  GenServer.
- No test pins the `:noproc` race: it cannot be caught in a suite. Tests
  pin that a linked crash starts no further request.
- The race is in Elixir, and unchanged on its main branch at this date. A
  fix there would settle the exit reason, but an ordered stream would
  still start requests after a failure.
