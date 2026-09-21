defmodule Cite.Cluster do
  @moduledoc """
  A typed compose cluster for Select.

  Built via `new/1`. `:questions` values must be `%Cite.Question{}`. A
  `%Cite.Candidate{}` anywhere in `:state` is wired as its `meta` plus `"id"`
  and `"text"`, and a list of candidates as an object keyed by id that keeps
  their order; put candidates there rather than building maps by hand.
  Empty `:questions` is allowed (atomic-only emit with no compare round).
  When `:member_questions` is non-empty, every id must name a member and
  every question key must name a Noul in `:questions` — only a Noul can clear
  the reject edge that grounds a member.
  """

  alias Cite.{Candidate, Question}

  @type t :: %__MODULE__{
          id: String.t(),
          class: String.t(),
          members: [Candidate.t()],
          state: map(),
          questions: %{optional(String.t()) => Question.t()},
          member_questions: %{optional(String.t()) => [String.t()]},
          match: :all | :any
        }

  @enforce_keys [:id, :class, :members, :state, :questions]
  defstruct [:id, :class, :members, :state, :questions, member_questions: %{}, match: :all]

  @required [:id, :class, :members, :state, :questions]
  @reserved_keys ["cluster_id", "compare", "review"]

  @doc """
  Builds a `%Cite.Cluster{}`. Raises `ArgumentError` on missing keys or bad types.
  """
  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_list(attrs) do
    unless Keyword.keyword?(attrs) do
      raise ArgumentError, "expected a keyword list, got: #{inspect(attrs)}"
    end

    attrs
    |> Map.new()
    |> new()
  end

  def new(attrs) when is_map(attrs) and not is_struct(attrs) do
    attrs = normalize_keys(attrs)
    require_keys(attrs)

    members = members(attrs.members)
    questions = questions(attrs.questions)
    member_question_keys = Map.get(attrs, :member_questions, %{})
    match_mode = Map.get(attrs, :match, :all)

    %__MODULE__{
      id: id(attrs.id),
      class: class(attrs.class),
      members: members,
      state: state(attrs.state),
      questions: questions,
      member_questions: member_questions(member_question_keys, members, questions),
      match: match(match_mode)
    }
  end

  def new(other) do
    raise ArgumentError, "expected a map or keyword list, got: #{inspect(other)}"
  end

  defp normalize_keys(attrs) do
    Map.new(attrs, fn
      {key, value} when is_atom(key) ->
        {key, value}

      {key, _value} when is_binary(key) ->
        raise ArgumentError, "cluster attr keys must be atoms, got string key: #{inspect(key)}"

      {key, _value} ->
        raise ArgumentError, "cluster attr keys must be atoms, got: #{inspect(key)}"
    end)
  end

  defp require_keys(attrs) do
    missing = Enum.reject(@required, &Map.has_key?(attrs, &1))

    if missing != [] do
      raise ArgumentError, "cluster is missing required keys: #{inspect(missing)}"
    end
  end

  defp id(id) when is_binary(id) and id != "", do: id

  defp id(id),
    do: raise(ArgumentError, "cluster id must be a non-empty binary, got: #{inspect(id)}")

  defp class(class) when is_binary(class) and class != "", do: class

  defp class(class) do
    raise ArgumentError, "cluster class must be a non-empty binary, got: #{inspect(class)}"
  end

  defp members([_ | _] = members) do
    unless Enum.all?(members, &match?(%Candidate{}, &1)) do
      raise ArgumentError, "cluster members must all be Cite.Candidate structs"
    end

    dupes = for {id, n} <- Enum.frequencies_by(members, & &1.id), n > 1, do: id

    case Enum.sort(dupes) do
      [] ->
        members

      sorted ->
        raise ArgumentError, "cluster member ids must be unique, duplicated: #{inspect(sorted)}"
    end
  end

  defp members([]), do: raise(ArgumentError, "cluster members must be a non-empty list")

  defp members(other) do
    raise ArgumentError,
          "cluster members must be a non-empty list of Candidates, got: #{inspect(other)}"
  end

  defp state(state) when is_map(state) and not is_struct(state), do: state

  defp state(other),
    do: raise(ArgumentError, "cluster state must be a map, got: #{inspect(other)}")

  defp questions(questions) when is_map(questions) and not is_struct(questions) do
    unless Enum.all?(questions, fn {key, value} ->
             is_binary(key) and key != "" and match?(%Question{}, value)
           end) do
      raise ArgumentError,
            "cluster questions must be %{non-empty binary => Cite.Question}"
    end

    reserved = Enum.filter(Map.keys(questions), &(&1 in @reserved_keys))

    if reserved != [] do
      raise ArgumentError,
            "cluster question keys #{inspect(Enum.sort(reserved))} are reserved for span attributes"
    end

    questions
  end

  defp questions(other) do
    raise ArgumentError, "cluster questions must be a map, got: #{inspect(other)}"
  end

  defp member_questions(member_questions, members, questions)
       when is_map(member_questions) and not is_struct(member_questions) do
    unless member_questions_shape?(member_questions) do
      raise ArgumentError,
            "member_questions must be %{candidate_id => non-empty [question_key]}, got: #{inspect(member_questions)}"
    end

    member_questions
    |> Map.keys()
    |> ensure_subset(
      MapSet.new(members, & &1.id),
      "member_questions ids are not cluster members"
    )

    nouls = for {key, %Question{type: :noul}} <- questions, into: MapSet.new(), do: key

    member_questions
    |> Map.values()
    |> List.flatten()
    |> ensure_subset(
      nouls,
      "member_questions must name Noul questions; these are not Nouls or not in questions"
    )

    member_questions
  end

  defp member_questions(other, _members, _questions) do
    raise ArgumentError, "member_questions must be a map, got: #{inspect(other)}"
  end

  defp member_questions_shape?(member_questions) do
    Enum.all?(member_questions, fn {candidate_id, question_keys} ->
      is_binary(candidate_id) and is_list(question_keys) and question_keys != [] and
        Enum.all?(question_keys, &(is_binary(&1) and &1 != ""))
    end)
  end

  defp ensure_subset(values, allowed, message) do
    unknown =
      values
      |> Enum.uniq()
      |> Enum.reject(&MapSet.member?(allowed, &1))
      |> Enum.sort()

    case unknown do
      [] -> :ok
      _ -> raise ArgumentError, "#{message}: #{inspect(unknown)}"
    end
  end

  defp match(:all), do: :all
  defp match(:any), do: :any

  defp match(other) do
    raise ArgumentError, "cluster match must be :all or :any, got: #{inspect(other)}"
  end
end
