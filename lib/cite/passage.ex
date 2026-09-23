defmodule Cite.Passage do
  @moduledoc """
  One unit of a `Cite.Source`: the caller's id, exact text, and meta.

  A citation is a passage, unchanged. Built by `Cite.source/2`; read it,
  don't build it.
  """

  @derive {Jason.Encoder, only: [:id, :text, :meta]}

  @type t :: %__MODULE__{id: String.t(), text: String.t(), meta: map()}

  @enforce_keys [:id, :text]
  defstruct [:id, :text, meta: %{}]
end
