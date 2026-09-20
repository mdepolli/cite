defmodule Cite.Wire do
  # Values → judge request maps. The only place atom keys become strings and
  # structs become their wire shape; nothing past this edge sees an Elixir value.
  @moduledoc false

  alias Cite.{Candidate, Question}

  @doc """
  Stringifies keys recursively. A `%Candidate{}` anywhere in the tree becomes
  its wire shape via `candidate/1`.
  """
  @spec map(map()) :: map()
  def map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {key(key), value(value)} end)
  end

  @doc """
  A candidate on the wire: its `meta` (keys stringified) plus `"id"` and `"text"`.
  """
  @spec candidate(Candidate.t()) :: map()
  def candidate(%Candidate{id: id, text: text, meta: meta}) do
    meta
    |> map()
    |> Map.put("id", id)
    |> Map.put("text", text)
  end

  @doc """
  Encodes every question in a `%{key => Question.t()}` map.
  """
  @spec questions(%{String.t() => Question.t()}) :: %{String.t() => map()}
  def questions(questions) do
    Map.new(questions, fn {key, %Question{} = question} -> {key, Question.encode(question)} end)
  end

  defp key(key) when is_atom(key), do: Atom.to_string(key)
  defp key(key) when is_binary(key), do: key

  defp value(%Candidate{} = candidate), do: candidate(candidate)
  defp value(%{} = map) when not is_struct(map), do: map(map)
  defp value(list) when is_list(list), do: Enum.map(list, &value/1)
  defp value(value), do: value
end
