defmodule Cite.Policy.Terms do
  @moduledoc """
  A policy's terms: its filters, concerns, factors, and descriptors as data,
  defaults filled in, compiled from the module that declares them. What the
  rounds read. Built by `Cite.Policy.Build`; read it with
  `Cite.Policy.Build.read/1`. Internal.
  """

  alias Cite.Policy.{Concern, Question}

  @type t :: %__MODULE__{
          filters: [{atom(), Question.t()}],
          concerns: [Concern.t()],
          factors: [{atom(), Question.t()}],
          descriptors: [{atom(), Question.t()}]
        }

  defstruct filters: [], concerns: [], factors: [], descriptors: []
end
