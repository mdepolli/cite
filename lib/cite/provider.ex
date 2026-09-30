defmodule Cite.Provider do
  @moduledoc """
  A decision-model provider: builds a handle, then answers one wire-shaped
  request per call.

  `Cite.client/2` turns a provider into the client, the 1-arity function
  `Cite.judge/4` takes. The rounds never see the provider's own handle.
  `Cite.judge/4` may call `judge/2` from several processes at once with the
  same handle. Implementations: `Cite.Provider.TypeSafe`.

  ## Requests

  The request follows the question schema of TypeSafe's System One API:
  `"state"` plus `"questions"`. A value in `"state"` may be a
  `Cite.Wire.Object`, a JSON object that keeps its keys in order. Each
  question is a map with `"type"` (`noul`, `score`, `choice`),
  `"instructions"` (`question`, then `inspect` or `compare`, and an optional
  `focus`), and `"criteria"`.

  Cite encodes questions to that schema before they reach a provider, so a
  provider never sees a policy. A provider for a model that takes the schema
  sends it as is. One for a model with different inputs converts from it.

  ## Errors

  A provider raises on caller error, such as bad options. It returns
  `{:error, reason}` for anything the network did: a failed call, or a
  reply Cite cannot read. `Cite.judge/4` records those as `Cite.Error`s and
  carries on. A provider must not raise on a condition that concurrency
  makes routine, such as waiting for a connection.

  One reason is shared across providers: `:request_too_large`, meaning the
  request exceeded the provider's size cap. Round 1 halves its window and
  retries on it, so a provider must map its own overflow signal to that
  atom.
  """

  @type reason :: :request_too_large | term()

  @doc "Builds the provider's handle from options. Raises on bad options."
  @callback new(keyword()) :: handle :: term()

  @doc """
  Answers a request of `%{"state" => map(), "questions" => map()}`, where a
  value in `"state"` may be a `Cite.Wire.Object`.
  """
  @callback judge(handle :: term(), request :: map()) ::
              {:ok, Cite.verdict()} | {:error, reason()}
end
