defmodule Cite.Candidate do
  @moduledoc """
  A source slice proposed for judgment, with byte offsets into a joined document.

  Build candidates with `from_segments/1`. `meta` is caller-owned (speaker, times,
  …); this module does not interpret it.
  """

  @typedoc """
  Input row for `from_segments/1`. Atom keys only.

  Missing `:id` defaults to `C000`, `C001`, … by position; missing `:meta`
  defaults to `%{}`. `:text` is trimmed; blank-after-trim is rejected. A present
  `:id` must be a non-empty binary.
  """
  @type segment :: %{
          required(:text) => String.t(),
          optional(:id) => String.t(),
          optional(:meta) => map()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          text: String.t(),
          byte_start: non_neg_integer(),
          byte_end: non_neg_integer(),
          meta: map()
        }

  @enforce_keys [:id, :text, :byte_start, :byte_end]
  defstruct [:id, :text, :byte_start, :byte_end, meta: %{}]

  @doc """
  Joins `segment` texts into one `source` and returns `{source, candidates}`.

  Each `:text` is trimmed, then joined with a single ASCII space (`0x20`).
  Offsets are **byte** indexes into `source`. For every candidate,
  `binary_part(source, byte_start, byte_end - byte_start) == text`.
  `[]` → `{"", []}`.

  Raises `ArgumentError` on a bad list or segment (programmer error), including
  blank-after-trim `:text` or an empty `:id`.
  """
  @spec from_segments([segment()]) :: {String.t(), [t()]}
  def from_segments(segments) when is_list(segments) do
    {source, candidates, _offset} =
      segments
      |> Enum.with_index()
      |> Enum.reduce({"", [], 0}, &append_segment/2)

    {source, Enum.reverse(candidates)}
  end

  def from_segments(other) do
    raise ArgumentError, "expected a list of segments, got: #{inspect(other)}"
  end

  defp append_segment({segment, index}, {acc, candidates, offset}) do
    text = segment_text!(segment)
    id = segment_id!(segment, index)
    meta = segment_meta!(segment)

    start_offset = if acc == "", do: 0, else: offset + 1
    source = if acc == "", do: text, else: acc <> " " <> text
    byte_end = start_offset + byte_size(text)

    candidate = %__MODULE__{
      id: id,
      text: text,
      byte_start: start_offset,
      byte_end: byte_end,
      meta: meta
    }

    {source, [candidate | candidates], byte_end}
  end

  defp segment_text!(%{text: text}) when is_binary(text) do
    case String.trim(text) do
      "" ->
        raise ArgumentError, "segment :text is blank after trim, got: #{inspect(text)}"

      trimmed ->
        trimmed
    end
  end

  defp segment_text!(%{text: other}) do
    raise ArgumentError, "segment :text must be a binary, got: #{inspect(other)}"
  end

  defp segment_text!(segment) when is_map(segment) do
    raise ArgumentError, "segment is missing required :text key, got: #{inspect(segment)}"
  end

  defp segment_text!(other) do
    raise ArgumentError, "segment must be a map, got: #{inspect(other)}"
  end

  defp segment_id!(%{id: id}, _index) when is_binary(id) and id != "" do
    id
  end

  defp segment_id!(%{id: ""}, _index) do
    raise ArgumentError, ~s(segment :id must be a non-empty binary, got: "")
  end

  defp segment_id!(%{id: other}, _index) do
    raise ArgumentError, "segment :id must be a binary, got: #{inspect(other)}"
  end

  defp segment_id!(_segment, index), do: auto_id(index)

  defp segment_meta!(%{meta: meta}) when is_map(meta), do: meta

  defp segment_meta!(%{meta: other}) do
    raise ArgumentError, "segment :meta must be a map, got: #{inspect(other)}"
  end

  defp segment_meta!(_segment), do: %{}

  defp auto_id(index) do
    "C" <> String.pad_leading(Integer.to_string(index), 3, "0")
  end
end
