defmodule Cite.Error do
  @moduledoc """
  A failed request: the concern it was judging (`nil` for a screening
  window), the passages it covered, and the reason. A failed request is
  never a verdict; it lands in `Cite.Report.errors` and nowhere else.

  `reason` is whatever the provider returned, or `{:missing_answers, keys}`
  / `{:malformed_answers, keys}` when a reply skipped a question or answered
  one in a shape its type cannot have. Encoding always succeeds: JSON-safe
  reasons pass through, everything else becomes `inspect(reason)`.
  """

  @type t :: %__MODULE__{
          concern: atom() | nil,
          passage_ids: [String.t()],
          reason: term()
        }

  @enforce_keys [:concern, :passage_ids, :reason]
  defstruct [:concern, :passage_ids, :reason]

  @doc false
  @spec to_json_map(t()) :: map()
  def to_json_map(%__MODULE__{} = error) do
    %{
      "concern" => error.concern,
      "passage_ids" => error.passage_ids,
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
