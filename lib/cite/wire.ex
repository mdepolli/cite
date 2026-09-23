defmodule Cite.Wire do
  @moduledoc """
  Values to request maps.

  The one place atom keys become strings and a `Cite.Candidate` becomes its
  wire shape; nothing past this edge sees an Elixir value. Internal.
  """

  alias Cite.{Candidate, Passage, Placeholder, Question}
  alias Cite.Policy.Question, as: PolicyQuestion
  alias Cite.Wire.Object

  @doc """
  Passages on the wire as one object keyed by id, in source order, each with
  only the meta keys `show` names.
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
    |> map()
    |> Map.put("id", id)
    |> Map.put("text", text)
  end

  @doc """
  One compiled question on the wire. `paths` maps each placeholder name to
  its path in the request's state; a question with no placeholders compares
  the `fallback` paths.
  """
  @spec question(PolicyQuestion.t(), %{String.t() => String.t()}, [String.t()]) :: map()
  def question(%PolicyQuestion{} = question, paths, fallback) do
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

  @doc """
  Stringifies keys recursively. A `%Candidate{}` anywhere in the tree becomes
  its wire shape via `candidate/1`; a list of candidates becomes an object
  keyed by id that keeps their order (`candidates/1`).
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

  def candidate(other) do
    raise ArgumentError, "expected a Cite.Candidate in state, got: #{inspect(other)}"
  end

  @doc """
  Candidates on the wire as one object keyed by id, in the order given. A
  plain map would lose that order past 32 entries.
  """
  @spec candidates([Candidate.t()]) :: Object.t()
  def candidates(candidates) when is_list(candidates) do
    Object.new(
      for candidate <- candidates do
        wired = candidate(candidate)
        {candidate.id, wired}
      end
    )
  end

  @doc """
  Encodes every question in a `%{key => Question.t()}` map.
  """
  @spec questions(%{String.t() => Question.t()}) :: %{String.t() => map()}
  def questions(questions) do
    Map.new(questions, fn {key, %Question{} = question} -> {key, Question.encode(question)} end)
  end

  @doc "A state or meta key on the wire: atoms become strings, binaries stay."
  @spec key(atom() | String.t()) :: String.t()
  def key(key) when is_atom(key), do: Atom.to_string(key)
  def key(key) when is_binary(key), do: key

  def key(other) do
    raise ArgumentError, "state and meta keys must be atoms or binaries, got: #{inspect(other)}"
  end

  defp value(%Candidate{} = candidate), do: candidate(candidate)
  defp value(%Object{} = object), do: object

  defp value(%{} = map) when not is_struct(map), do: map(map)

  defp value(%{__struct__: module}) do
    raise ArgumentError,
          "state and meta may hold plain maps, lists, scalars, and candidates; got a #{inspect(module)} struct"
  end

  defp value([%Candidate{} | _] = candidates), do: candidates(candidates)
  defp value(list) when is_list(list), do: Enum.map(list, &value/1)
  defp value(value), do: value

  defp put_focus(instructions, nil, _paths), do: instructions

  defp put_focus(instructions, focus, paths),
    do: Map.put(instructions, "focus", Placeholder.expand(focus, paths))

  defp criteria(:noul, %{true: yes, false: no}), do: %{"true" => map(yes), "false" => map(no)}
  defp criteria(_type, criteria), do: criteria
end
