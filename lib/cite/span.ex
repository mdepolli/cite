defmodule Cite.Span do
  @moduledoc """
  A grounded slice of source text with byte offsets.

  Returned by `Cite.select/5`, one per grounded cluster member, with the
  cluster's `class` and the labelled compare answers as `attributes`.

  Offsets and `candidate_id` are always present — Cite only emits
  byte-exact copies, never aligner statuses or unlocated spans.
  """

  alias Cite.Candidate

  @derive [
    {Jason.Encoder, only: [:text, :byte_start, :byte_end, :candidate_id, :class, :attributes]},
    {JSON.Encoder, only: [:text, :byte_start, :byte_end, :candidate_id, :class, :attributes]}
  ]

  @type t :: %__MODULE__{
          text: String.t(),
          byte_start: non_neg_integer(),
          byte_end: non_neg_integer(),
          candidate_id: String.t(),
          class: String.t() | nil,
          attributes: map()
        }

  @enforce_keys [:text, :byte_start, :byte_end, :candidate_id]
  defstruct [:text, :byte_start, :byte_end, :candidate_id, :class, attributes: %{}]

  # Select's grounding step: a byte-exact copy of each candidate. Offsets
  # are trusted — Cite.Scan.candidates/2 has already checked every one
  # against this source, before any judge call.
  @doc false
  @spec from_candidates(String.t(), [Candidate.t()]) :: [t()]
  def from_candidates(source, candidates) when is_binary(source) and is_list(candidates) do
    Enum.map(candidates, &from_candidate(source, &1))
  end

  defp from_candidate(source, %Candidate{id: id, byte_start: start, byte_end: stop}) do
    %__MODULE__{
      text: binary_part(source, start, stop - start),
      byte_start: start,
      byte_end: stop,
      candidate_id: id
    }
  end
end
