defmodule Cite.Wire do
  @moduledoc """
  Values to request maps.

  The one place passages and compiled questions become the maps a client
  receives: atom keys become strings, placeholders become backticked paths.
  Nothing past this edge sees an Elixir struct. Internal.
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

  @doc """
  One compiled question on the wire. `paths` maps each placeholder name to
  its path in the request's state; a question with no placeholders compares
  the `fallback` paths.
  """
  @spec question(Question.t(), %{String.t() => String.t()}, [String.t()]) :: map()
  def question(%Question{} = question, paths, fallback) do
    instructions =
      question.text
      |> Placeholder.instructions(paths, fallback)
      |> put_focus(question.focus, paths)

    %{
      "type" => Atom.to_string(question.type),
      "instructions" => instructions,
      "criteria" => criteria(question.type, question.criteria)
    }
  end

  defp put_focus(instructions, nil, _paths), do: instructions

  defp put_focus(instructions, focus, paths),
    do: Map.put(instructions, "focus", Placeholder.expand(focus, paths))

  defp criteria(:noul, %{true: yes, false: no}),
    do: %{"true" => stringify(yes), "false" => stringify(no)}

  defp criteria(_type, criteria), do: criteria

  defp stringify(map) do
    Map.new(map, fn {key, value} -> {key(key), value(value)} end)
  end

  defp key(key) when is_atom(key), do: Atom.to_string(key)
  defp key(key) when is_binary(key), do: key

  defp key(other) do
    raise ArgumentError, "meta keys must be atoms or binaries, got: #{inspect(other)}"
  end

  defp value(%{} = map) when not is_struct(map), do: stringify(map)

  defp value(%{__struct__: module}) do
    raise ArgumentError,
          "shown meta may hold plain maps, lists, and scalars; got a #{inspect(module)} struct"
  end

  defp value(list) when is_list(list), do: Enum.map(list, &value/1)
  defp value(value), do: value
end
