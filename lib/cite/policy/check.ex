defmodule Cite.Policy.Check do
  @moduledoc """
  A compiled check: its name, whether its roles must be distinct passages,
  the roles its question names, and the question. Internal.
  """

  alias Cite.Policy.Question

  @type t :: %__MODULE__{
          name: atom(),
          distinct: boolean(),
          roles: [atom()],
          question: Question.t()
        }

  @enforce_keys [:name, :roles, :question]
  defstruct [:name, :roles, :question, distinct: false]
end
