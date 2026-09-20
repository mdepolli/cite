defmodule Cite.Provider do
  @moduledoc """
  A decision-model provider: builds a handle, then answers one wire-shaped
  request at a time.

  `Cite.new/2` turns a provider into the client — the 1-arity function
  `Cite.select/5` takes — so the pipeline never sees the provider's own
  handle. Implementations: `Cite.Provider.TypeSafe`.

  ## Requests

  The request is the question schema TypeSafe's System One API defined and
  Laya adopted: `"state"` plus
  `"questions"`, each question a map with `"type"` (`noul`, `score`,
  `choice`), `"instructions"` (`question`, `inspect`) and `"criteria"`.
  TypeSafe Jev and Laya share it, so a provider for either sends it as is; a
  provider for a model with different inputs converts from it. Cite encodes
  questions to that schema before they reach a provider; the provider never
  sees a `Cite.Question` struct.

  ## Errors

  A provider raises on caller error (bad options) and returns `{:error,
  reason}` for anything the network did — a failed call, a reply Cite cannot
  read. `Cite.select/5` records those as `Cite.Error`s and carries on.

  One reason is shared across providers: `:request_too_large`, meaning the
  request exceeded the provider's size cap. The pipeline halves the window
  and retries on it, so a provider must map its own overflow signal to that
  atom.
  """

  @type reason :: :request_too_large | term()

  @doc "Builds the provider's handle from options. Bad options are a caller error and raise."
  @callback new(keyword()) :: handle :: term()

  @doc """
  Answers a request of `%{"state" => map(), "questions" => map()}`.
  """
  @callback judge(handle :: term(), request :: map()) ::
              {:ok, Cite.verdict()} | {:error, reason()}
end
