defmodule Cite.Passage do
  @moduledoc """
  One unit of a `Cite.Source`: the caller's id, exact text, and meta.

  A citation is a passage, unchanged. Built by `Cite.source/2`. Read it,
  don't build it.

  `meta` is kept as given. Encoding a passage, or a report, with Jason needs
  every value in it to be encodable. A tuple or a pid is not.
  """

  @derive {Jason.Encoder, only: [:id, :text, :meta]}

  @type t :: %__MODULE__{id: String.t(), text: String.t(), meta: map()}

  @enforce_keys [:id, :text]
  defstruct [:id, :text, meta: %{}]
end
