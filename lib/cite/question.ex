defmodule Cite.Question do
  @moduledoc """
  A typed System One question.

  Callers build `%Cite.Question{}` via `noul/1`, `score/1`, or `choice/1`
  and hand them to `Cite.select/5` in the spec; Cite encodes them to the wire
  at the judge edge, so callers never see string keys.
  """

  @type type :: :noul | :score | :choice
  @type inspect_path :: String.t() | [String.t()]

  @type noul_criteria :: %{
          required(:what) => String.t(),
          optional(:not_for) => String.t(),
          optional(:examples) => [String.t()]
        }

  @type criteria ::
          %{required(true) => noul_criteria(), required(false) => noul_criteria()}
          | [String.t()]
          | %{required(String.t()) => String.t()}

  @type t :: %__MODULE__{
          type: type(),
          question: String.t(),
          inspect: inspect_path(),
          criteria: criteria()
        }

  @enforce_keys [:type, :question, :inspect, :criteria]
  defstruct [:type, :question, :inspect, :criteria]

  @criteria_keys [:what, :not_for, :examples]

  @doc """
  Builds a `:noul` question.

  Required opts: `:question`, `:inspect`, `:true`, `:false`.
  """
  @spec noul(keyword()) :: t()
  def noul(opts) when is_list(opts) do
    opts = Keyword.validate!(opts, [:question, :inspect, true, false])

    %__MODULE__{
      type: :noul,
      question: question(fetch_opt(opts, :question)),
      inspect: inspect_path(fetch_opt(opts, :inspect)),
      criteria: %{
        true: criteria(fetch_opt(opts, true)),
        false: criteria(fetch_opt(opts, false))
      }
    }
  end

  def noul(other) do
    raise ArgumentError, "noul expects a keyword list, got: #{inspect(other)}"
  end

  @doc """
  Builds a `:score` question.

  Required opts: `:question`, `:inspect`, `:criteria` (2–10 non-empty band labels).
  """
  @spec score(keyword()) :: t()
  def score(opts) when is_list(opts) do
    opts = Keyword.validate!(opts, [:question, :inspect, :criteria])

    %__MODULE__{
      type: :score,
      question: question(fetch_opt(opts, :question)),
      inspect: inspect_path(fetch_opt(opts, :inspect)),
      criteria: score_criteria(fetch_opt(opts, :criteria))
    }
  end

  def score(other) do
    raise ArgumentError, "score expects a keyword list, got: #{inspect(other)}"
  end

  @doc """
  Builds a `:choice` question.

  Required opts: `:question`, `:inspect`, `:criteria` (non-empty map of option id => description).
  Option ids stay binaries (dynamic).
  """
  @spec choice(keyword()) :: t()
  def choice(opts) when is_list(opts) do
    opts = Keyword.validate!(opts, [:question, :inspect, :criteria])

    %__MODULE__{
      type: :choice,
      question: question(fetch_opt(opts, :question)),
      inspect: inspect_path(fetch_opt(opts, :inspect)),
      criteria: choice_criteria(fetch_opt(opts, :criteria))
    }
  end

  def choice(other) do
    raise ArgumentError, "choice expects a keyword list, got: #{inspect(other)}"
  end

  # Jev's wire JSON map (string keys). Called by Cite.Wire only.
  @doc false
  @spec encode(t()) :: map()
  def encode(%__MODULE__{type: type, question: question, inspect: inspect, criteria: criteria})
      when type in [:noul, :score, :choice] do
    %{
      "type" => Atom.to_string(type),
      "instructions" => %{
        "question" => question,
        "inspect" => inspect
      },
      "criteria" => encode_criteria(type, criteria)
    }
  end

  def encode(other) do
    raise ArgumentError, "expected a Cite.Question, got: #{inspect(other)}"
  end

  defp fetch_opt(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "missing required key: #{inspect(key)}"
    end
  end

  defp encode_criteria(:noul, %{true: yes, false: no}) do
    %{"true" => stringify_criteria(yes), "false" => stringify_criteria(no)}
  end

  defp encode_criteria(:score, criteria), do: criteria
  defp encode_criteria(:choice, criteria), do: criteria

  defp stringify_criteria(criteria) when is_map(criteria) do
    Map.new(criteria, fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp question(question) when is_binary(question) and question != "", do: question

  defp question(other) do
    raise ArgumentError, "question must be a non-empty binary, got: #{inspect(other)}"
  end

  defp inspect_path(path) when is_binary(path) and path != "", do: path

  defp inspect_path(path) when is_binary(path) do
    raise ArgumentError, "inspect must be a non-empty binary, got: #{inspect(path)}"
  end

  defp inspect_path(paths) when is_list(paths) do
    cond do
      paths == [] ->
        raise ArgumentError, "inspect list must be non-empty"

      Enum.all?(paths, &(is_binary(&1) and &1 != "")) ->
        paths

      true ->
        raise ArgumentError,
              "inspect list must contain only non-empty binaries, got: #{inspect(paths)}"
    end
  end

  defp inspect_path(other) do
    raise ArgumentError,
          "inspect must be a binary or a list of binaries, got: #{inspect(other)}"
  end

  defp criteria(what) when is_binary(what) and what != "", do: %{what: what}

  defp criteria(what) when is_binary(what) do
    raise ArgumentError, "criteria what must be a non-empty binary, got: #{inspect(what)}"
  end

  defp criteria(structured) when is_map(structured) and not is_struct(structured) do
    structured = normalize_criteria_keys(structured)
    what = Map.get(structured, :what)

    unless is_binary(what) and what != "" do
      raise ArgumentError, "criteria what must be a non-empty binary, got: #{inspect(what)}"
    end

    unknown = Map.keys(structured) -- @criteria_keys

    if unknown != [] do
      raise ArgumentError,
            "criteria has unknown keys: #{inspect(Enum.sort(unknown))}; allowed: #{inspect(@criteria_keys)}"
    end

    validate_criteria_fields(structured)
    structured
  end

  defp criteria(other) do
    raise ArgumentError,
          "criteria must be a binary what or a map with :what, got: #{inspect(other)}"
  end

  defp normalize_criteria_keys(structured) do
    Map.new(structured, fn
      {key, value} when is_atom(key) ->
        {key, value}

      {key, _value} when is_binary(key) ->
        raise ArgumentError,
              "criteria keys must be atoms, got string key: #{inspect(key)}"

      {key, _value} ->
        raise ArgumentError, "criteria keys must be atoms, got: #{inspect(key)}"
    end)
  end

  defp validate_criteria_fields(structured) do
    if Map.has_key?(structured, :not_for) do
      not_for = structured[:not_for]

      unless is_binary(not_for) and not_for != "" do
        raise ArgumentError,
              "criteria not_for must be a non-empty binary, got: #{inspect(not_for)}"
      end
    end

    if Map.has_key?(structured, :examples) do
      examples = structured[:examples]

      unless is_list(examples) and examples != [] and
               Enum.all?(examples, &(is_binary(&1) and &1 != "")) do
        raise ArgumentError,
              "criteria examples must be a non-empty list of non-empty binaries, got: #{inspect(examples)}"
      end
    end

    :ok
  end

  defp score_criteria(criteria) when is_list(criteria) do
    length = length(criteria)

    unless length in 2..10 do
      raise ArgumentError,
            "score criteria must have 2..10 labels, got #{length}: #{inspect(criteria)}"
    end

    unless Enum.all?(criteria, &(is_binary(&1) and &1 != "")) do
      raise ArgumentError,
            "score criteria must be a list of non-empty binaries, got: #{inspect(criteria)}"
    end

    dupes = for {label, n} <- Enum.frequencies(criteria), n > 1, do: label

    case Enum.sort(dupes) do
      [] ->
        criteria

      sorted ->
        raise ArgumentError,
              "score criteria labels must be unique, duplicated: #{inspect(sorted)}"
    end
  end

  defp score_criteria(criteria) do
    raise ArgumentError,
          "score criteria must be a list of 2..10 binaries, got: #{inspect(criteria)}"
  end

  defp choice_criteria(criteria) when is_map(criteria) and map_size(criteria) > 0 do
    unless Enum.all?(criteria, fn {k, v} ->
             is_binary(k) and k != "" and is_binary(v) and v != ""
           end) do
      raise ArgumentError,
            "choice criteria must be a map of non-empty binary => non-empty binary, got: #{inspect(criteria)}"
    end

    criteria
  end

  defp choice_criteria(criteria) do
    raise ArgumentError,
          "choice criteria must be a non-empty map of binary => binary, got: #{inspect(criteria)}"
  end
end
