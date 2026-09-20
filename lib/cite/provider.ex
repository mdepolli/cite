defmodule Cite.Provider do
  @moduledoc """
  A System One provider: builds a client, then answers one wire-shaped
  request at a time.

  `Cite.judge/2` turns a provider into the 1-arity function `Cite.select/5`
  takes, so the pipeline never sees the client. Implementations:
  `Cite.Provider.TypeSafe`.

  ## Requests

  The request is the System One question schema: `"state"` plus
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

  @doc "Builds a client from options. Bad options are a caller error and raise."
  @callback new(keyword()) :: client :: term()

  @doc """
  Answers a request of `%{"state" => map(), "questions" => map()}`.
  """
  @callback judge(client :: term(), request :: map()) ::
              {:ok, Cite.verdict()} | {:error, reason()}
end
