defmodule Cite.Policy.Concern do
  @moduledoc """
  One compiled concern: screened directly (`detect` and `confirm`) or built
  from factors (`roles` and `checks`). Internal.
  """

  alias Cite.Policy.{Check, Question, Role}

  @type t :: %__MODULE__{
          name: atom(),
          category: atom(),
          detect: Question.t() | nil,
          confirm: Question.t() | nil,
          roles: [Role.t()],
          checks: [Check.t()]
        }

  @enforce_keys [:name, :category]
  defstruct [:name, :category, :detect, :confirm, roles: [], checks: []]
end
