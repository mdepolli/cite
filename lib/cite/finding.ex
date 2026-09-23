defmodule Cite.Finding do
  @moduledoc """
  A judged finding: its concern and category, the verdict, the raw answers
  to its checks and descriptors, the passages it cites, those its fit
  dropped, and the matches past `max_evidence` that were never judged.

  `checks` holds only the checks that were asked. Answers are the model's
  maps, string keys as they came off the wire. Read it, don't build it.
  """

  alias Cite.{Citation, Passage}

  @derive Jason.Encoder

  @type t :: %__MODULE__{
          concern: atom(),
          category: atom(),
          verdict: :holds | :review | :fails,
          checks: %{atom() => map()},
          descriptors: %{atom() => map()},
          evidence: [Citation.t()],
          dropped: [Citation.t()],
          over_cap: [Passage.t()]
        }

  @enforce_keys [:concern, :category, :verdict]
  defstruct [
    :concern,
    :category,
    :verdict,
    checks: %{},
    descriptors: %{},
    evidence: [],
    dropped: [],
    over_cap: []
  ]
end
