defmodule Cite.Policy.Concern do
  @moduledoc """
  One compiled concern: screened directly (`indicator` and `fit`) or built
  from factors (`roles` and `checks`). Internal.
  """

  alias Cite.Policy.{Check, Question, Role}

  @type t :: %__MODULE__{
          name: atom(),
          category: atom(),
          indicator: Question.t() | nil,
          fit: Question.t() | nil,
          roles: [Role.t()],
          checks: [Check.t()]
        }

  @enforce_keys [:name, :category]
  defstruct [:name, :category, :indicator, :fit, roles: [], checks: []]
end
