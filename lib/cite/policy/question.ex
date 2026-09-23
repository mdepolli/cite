defmodule Cite.Policy.Question do
  @moduledoc """
  One compiled question: its type, its text with placeholders unexpanded,
  its optional focus, and its criteria. Internal.
  """

  @type t :: %__MODULE__{
          type: :noul | :score | :choice,
          text: String.t(),
          focus: String.t() | nil,
          criteria: map() | [String.t()]
        }

  @enforce_keys [:type, :text, :criteria]
  defstruct [:type, :text, :criteria, focus: nil]
end
