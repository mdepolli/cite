defmodule Cite.Wire do
  @moduledoc """
  Values to request maps.

  The one place passages and compiled questions become the maps a client
  receives: atom keys become strings, and placeholders become backticked
  paths, built by `text_path/1` and `text_path/2`. Past this edge a client
  sees string-keyed maps, lists, and scalars, and a `Cite.Wire.Object`
  wherever key order matters. Internal.
  """

  alias Cite.{Passage, Placeholder}
  alias Cite.Policy.Question
  alias Cite.Wire.Object

  @doc """
  Passages on the wire as one object keyed by id, in source order, each with
  only the meta keys `show` names. A plain map would lose that order past
  32 entries, and the model reads neighbours.
  """
  @spec passages([Passage.t()], [atom() | String.t()]) :: Object.t()
  def passages(passages, show) when is_list(passages) do
    Object.new(for passage <- passages, do: {passage.id, passage(passage, show)})
  end

  @doc "One passage on the wire: `id`, `text`, and the meta keys `show` names."
  @spec passage(Passage.t(), [atom() | String.t()]) :: map()
  def passage(%Passage{id: id, text: text, meta: meta}, show) do
    meta
    |> Map.take(show)
    |> stringify()
    |> Map.put("id", id)
    |> Map.put("text", text)
  end

  @doc "The path to a passage's text under the source's `as`: `utterances.U014.text`."
  @spec text_path(String.t(), String.t()) :: String.t()
  def text_path(as, id), do: "#{as}.#{id}.text"

  @doc "The path to the text of the passage filling a role: `household.text`."
  @spec text_path(atom()) :: String.t()
  def text_path(role) when is_atom(role), do: "#{role}.text"

  @doc """
  One compiled question on the wire. `paths` maps each placeholder name to
  its path in the request's state; a question with no placeholders in its
  text or focus compares the `fallback` paths.
  """
  @spec question(Question.t(), %{String.t() => String.t()}, [String.t()]) :: map()
  def question(%Question{} = question, paths, fallback) do
    %{
      "type" => Atom.to_string(question.type),
      "instructions" => Placeholder.instructions(question.text, question.focus, paths, fallback),
      "criteria" => criteria(question.type, question.criteria)
    }
  end

  defp criteria(:noul, %{true: yes, false: no}),
    do: %{"true" => stringify(yes), "false" => stringify(no)}

  defp criteria(_type, criteria), do: criteria

  defp stringify(map) do
    Map.new(map, fn {key, value} -> {key(key), value(value)} end)
  end

  # `Cite.Source` has already checked shown meta is JSON, so only atom keys
  # need turning into strings.
  defp key(key) when is_atom(key), do: Atom.to_string(key)
  defp key(key), do: key

  defp value(%{} = map), do: stringify(map)
  defp value(list) when is_list(list), do: Enum.map(list, &value/1)
  defp value(value), do: value
end
