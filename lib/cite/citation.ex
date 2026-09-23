defmodule Cite.Citation do
  @moduledoc """
  One passage a finding cites, or dropped: the caller's passage, unchanged,
  its verdict, and the confirm answer that decided it (`nil` for a concern built
  from factors, whose passages are not judged one by one). Read it, don't
  build it.
  """

  alias Cite.Passage

  @derive Jason.Encoder

  @type t :: %__MODULE__{
          passage: Passage.t(),
          verdict: :holds | :review | :dropped,
          answer: map() | nil
        }

  @enforce_keys [:passage, :verdict]
  defstruct [:passage, :verdict, :answer]
end
