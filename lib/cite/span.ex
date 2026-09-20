defmodule Cite.Span do
  @moduledoc """
  A grounded slice of source text with byte offsets.

  Returned by `Cite.select/5`, one per grounded cluster member, with the
  cluster's `class` and the labelled compare answers as `attributes`.

  Offsets and `candidate_id` are always present — Cite only emits
  byte-exact copies, never aligner statuses or unlocated spans.
  """

  alias Cite.Candidate

  @derive {Jason.Encoder,
           only: [:text, :byte_start, :byte_end, :candidate_id, :class, :attributes]}

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

  # Select's grounding step. Raises ArgumentError on a non-list, a non-candidate,
  # invalid offsets, or a slice that does not equal candidate.text.
  @doc false
  @spec from_candidates(String.t(), [Candidate.t()]) :: [t()]
  def from_candidates(source, candidates) when is_binary(source) and is_list(candidates) do
    Enum.map(candidates, &from_candidate(source, &1))
  end

  def from_candidates(source, other) when is_binary(source) do
    raise ArgumentError, "expected a list of candidates, got: #{inspect(other)}"
  end

  defp from_candidate(source, %Candidate{
         id: id,
         text: expected,
         byte_start: start,
         byte_end: stop
       }) do
    text = source_slice(source, start, stop)

    if text != expected do
      raise ArgumentError,
            "candidate text does not match source slice at [#{start}, #{stop}): " <>
              "got #{inspect(text)}, expected #{inspect(expected)}"
    end

    %__MODULE__{
      text: text,
      byte_start: start,
      byte_end: stop,
      candidate_id: id
    }
  end

  defp from_candidate(_source, other) do
    raise ArgumentError, "expected a Candidate, got: #{inspect(other)}"
  end

  defp source_slice(source, start, stop)
       when is_integer(start) and is_integer(stop) and start >= 0 and stop >= start and
              stop <= byte_size(source) do
    binary_part(source, start, stop - start)
  end

  defp source_slice(source, start, stop) do
    raise ArgumentError,
          "invalid candidate offsets [#{inspect(start)}, #{inspect(stop)}) " <>
            "for source of #{byte_size(source)} bytes"
  end
end
