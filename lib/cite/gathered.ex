defmodule Cite.Gathered do
  @moduledoc """
  A finding gathered for judging, before round 2 makes it a `Cite.Finding`:
  its concern, the passages it would cite
  in source order, the passage filling each role (concerns built from
  factors), and the matches past `max_evidence`. Internal.
  """

  alias Cite.Passage
  alias Cite.Policy.Concern

  @type t :: %__MODULE__{
          concern: Concern.t(),
          passages: [Passage.t()],
          roles: %{atom() => Passage.t()},
          over_cap: [Passage.t()]
        }

  @enforce_keys [:concern, :passages]
  defstruct [:concern, :passages, roles: %{}, over_cap: []]
end
