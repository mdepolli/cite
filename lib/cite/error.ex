defmodule Cite.Error do
  @moduledoc """
  A failed request: the concern it was judging (`nil` for a screening
  window), the passages it covered, and the reason. A failed request is
  never a verdict; it lands in `Cite.Report.errors` and nowhere else.

  `reason` is whatever the provider returned, or `{:missing_answers, keys}`
  or `{:malformed_answers, keys}` when a reply skipped a question or
  answered one with a value its question cannot have. Encoding always succeeds:
  JSON-safe reasons pass through, everything else becomes `inspect(reason)`.
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

  defp reason_json(reason) when is_atom(reason) or is_number(reason), do: reason
  defp reason_json(reason) when is_binary(reason), do: utf8_or_inspect(reason)

  defp reason_json(reason) when is_list(reason) do
    if List.improper?(reason), do: inspect(reason), else: Enum.map(reason, &reason_json/1)
  end

  defp reason_json(%{} = reason) when not is_struct(reason) do
    Map.new(reason, fn {key, value} -> {key_json(key), reason_json(value)} end)
  end

  defp reason_json(reason), do: inspect(reason)

  defp key_json(key) when is_atom(key), do: key
  defp key_json(key) when is_binary(key), do: utf8_or_inspect(key)
  defp key_json(key), do: inspect(key)

  defp utf8_or_inspect(binary) do
    if String.valid?(binary), do: binary, else: inspect(binary)
  end
end

defimpl Jason.Encoder, for: Cite.Error do
  alias Cite.Error

  def encode(%Error{} = error, opts), do: Jason.Encode.map(Error.to_json_map(error), opts)
end
