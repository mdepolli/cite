defmodule Cite.Policy.Role do
  @moduledoc "A compiled role: its name, the factor that fills it, and its flags. Internal."

  @type t :: %__MODULE__{name: atom(), factor: atom(), optional: boolean(), distinct: boolean()}

  @enforce_keys [:name, :factor]
  defstruct [:name, :factor, optional: false, distinct: false]
end
