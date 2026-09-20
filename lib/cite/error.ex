defmodule Cite.Error do
  @moduledoc """
  A failed window or chunk with its byte range and reason.

  `reason` is open (`t:term/0`): whatever the failing layer reported.
  Encoding always succeeds — JSON-safe reasons pass through; everything
  else becomes `inspect(reason)`.
  """

  @type t :: %__MODULE__{
          byte_start: non_neg_integer(),
          byte_end: non_neg_integer(),
          reason: term()
        }

  @enforce_keys [:byte_start, :byte_end, :reason]
  defstruct [:byte_start, :byte_end, :reason]

  @doc """
  Builds an error for an explicit byte range.
  """
  @spec from_range(non_neg_integer(), non_neg_integer(), term()) :: t()
  def from_range(byte_start, byte_end, reason)
      when is_integer(byte_start) and byte_start >= 0 and is_integer(byte_end) and
             byte_end >= byte_start do
    %__MODULE__{byte_start: byte_start, byte_end: byte_end, reason: reason}
  end

  @doc false
  @spec from_candidates([Cite.Candidate.t(), ...], term()) :: t()
  def from_candidates([_ | _] = candidates, reason) do
    starts = Enum.map(candidates, & &1.byte_start)
    stops = Enum.map(candidates, & &1.byte_end)
    from_range(Enum.min(starts), Enum.max(stops), reason)
  end
end

defimpl Jason.Encoder, for: Cite.Error do
  def encode(%Cite.Error{} = error, opts) do
    Jason.Encode.map(
      %{
        "byte_start" => error.byte_start,
        "byte_end" => error.byte_end,
        "reason" => reason_json(error.reason)
      },
      opts
    )
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
