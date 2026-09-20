defmodule Cite.Error do
  @moduledoc """
  A failed judge call — a scan window or a compare cluster — with the byte
  range it covered, the candidates in it, and the reason. Returned in
  `Cite.Result.errors`.

  `candidate_ids` is the precise record: candidates need not be in document
  order, so the byte range of a failed window can overlap a candidate that
  was judged fine. `reason` is open (`t:term/0`): whatever the failing layer
  reported. Encoding always succeeds — JSON-safe reasons pass through;
  everything else becomes `inspect(reason)`.
  """

  alias Cite.Candidate

  @type t :: %__MODULE__{
          byte_start: non_neg_integer(),
          byte_end: non_neg_integer(),
          candidate_ids: [String.t()],
          reason: term()
        }

  @enforce_keys [:byte_start, :byte_end, :reason]
  defstruct [:byte_start, :byte_end, :reason, candidate_ids: []]

  @doc false
  @spec from_range(non_neg_integer(), non_neg_integer(), term()) :: t()
  def from_range(byte_start, byte_end, reason)
      when is_integer(byte_start) and byte_start >= 0 and is_integer(byte_end) and
             byte_end >= byte_start do
    %__MODULE__{byte_start: byte_start, byte_end: byte_end, reason: reason}
  end

  def from_range(byte_start, byte_end, _reason) do
    raise ArgumentError,
          "byte range must be non-negative integers with byte_end >= byte_start, " <>
            "got: [#{inspect(byte_start)}, #{inspect(byte_end)})"
  end

  @doc false
  @spec from_candidates([Candidate.t(), ...], term()) :: t()
  def from_candidates([_ | _] = candidates, reason) do
    starts = Enum.map(candidates, & &1.byte_start)
    stops = Enum.map(candidates, & &1.byte_end)
    error = from_range(Enum.min(starts), Enum.max(stops), reason)
    %__MODULE__{error | candidate_ids: Enum.map(candidates, & &1.id)}
  end

  # The one wire shape, for both encoders.
  @doc false
  @spec to_json_map(t()) :: map()
  def to_json_map(%__MODULE__{} = error) do
    %{
      "byte_start" => error.byte_start,
      "byte_end" => error.byte_end,
      "candidate_ids" => error.candidate_ids,
      "reason" => reason_json(error.reason)
    }
  end

  defp reason_json(reason) when is_atom(reason) or is_binary(reason) or is_number(reason) do
    reason
  end

  defp reason_json(reason) when is_list(reason), do: Enum.map(reason, &reason_json/1)

  defp reason_json(%{} = reason) when not is_struct(reason) do
    Map.new(reason, fn {key, value} -> {key, reason_json(value)} end)
  end

  defp reason_json(reason), do: inspect(reason)
end

defimpl Jason.Encoder, for: Cite.Error do
  alias Cite.Error

  def encode(%Error{} = error, opts), do: Jason.Encode.map(Error.to_json_map(error), opts)
end

defimpl JSON.Encoder, for: Cite.Error do
  alias Cite.Error

  def encode(%Error{} = error, encoder),
    do: JSON.Encoder.encode(Error.to_json_map(error), encoder)
end
