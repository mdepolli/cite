defmodule Cite.Finding do
  @moduledoc """
  A judged finding: its concern and category, the verdict, the raw answers
  to its checks and descriptors, the passages it cites, and those its
  confirm dropped. Every passage it gathered is in `evidence` or `dropped`.

  `checks` holds only the checks that were asked. Answers are the model's
  maps, with string keys as they came off the wire. Read it, don't build it.
  """

  alias Cite.Citation

  @derive Jason.Encoder

  @type t :: %__MODULE__{
          concern: atom(),
          category: atom(),
          verdict: :holds | :review | :fails,
          checks: %{atom() => map()},
          descriptors: %{atom() => map()},
          evidence: [Citation.t()],
          dropped: [Citation.t()]
        }

  @enforce_keys [:concern, :category, :verdict]
  defstruct [
    :concern,
    :category,
    :verdict,
    checks: %{},
    descriptors: %{},
    evidence: [],
    dropped: []
  ]
end
