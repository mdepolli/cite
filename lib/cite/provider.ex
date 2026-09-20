defmodule Cite.Provider do
  @moduledoc """
  A System One provider: builds a client, then answers one wire-shaped
  request at a time.

  `Cite.judge/2` turns a provider into the 1-arity function `Cite.select/5`
  takes, so the pipeline never sees the client. Implementations:
  `Cite.Provider.TypeSafe`.
  """

  @doc "Builds a client from options. Bad options are a caller error and raise."
  @callback new(keyword()) :: client :: term()

  @doc """
  Answers a request of `%{"state" => map(), "questions" => map()}`.
  """
  @callback judge(client :: term(), request :: map()) ::
              {:ok, Cite.verdict()} | {:error, term()}
end
