defmodule Cite.Scan do
  @moduledoc """
  The atomic scan, minus the client call.

  A window of candidates becomes one request (`request/3`); the judged
  outcomes become the score index (`resolve/2`); `drop_below/2` applies
  `atomic_threshold`. `atomics/1` and `candidates/2` are the checks
  `Cite.select/5` runs before its first request. Pure — tested with literal
  maps. Internal.
  """

  alias Cite.{Answer, Candidate, Error, Question, Wire}

  @type atomic :: %{name: String.t(), question: (Candidate.t() -> Question.t())}
  @type index :: %{String.t() => %{String.t() => number()}}
  @type outcome :: {[Candidate.t()], {:ok, map()} | {:error, term()}}

  @doc """
  Checks the caller's atomics: a non-empty list of `%{name, question}` with
  unique non-empty binary names (an atom would leak into the index as an
  atom key) and 1-arity question functions. Raises `ArgumentError`.
  """
  @spec atomics(term()) :: [atomic()]
  def atomics([_ | _] = atomics) do
    Enum.each(atomics, &atomic/1)
    dupes = for {name, n} <- Enum.frequencies_by(atomics, & &1.name), n > 1, do: name

    if dupes != [] do
      raise ArgumentError, "atomic names must be unique, duplicated: #{inspect(Enum.sort(dupes))}"
    end

    atomics
  end

  def atomics(other) do
    raise ArgumentError, "spec.atomics must be a non-empty list, got: #{inspect(other)}"
  end

  @doc """
  Checks the caller's candidates before any judge call is paid for: ids
  must be unique, or the scan would collapse two candidates into one row,
  and every `[byte_start, byte_end)` must slice `source` to exactly `text`,
  or the spans emitted at the end would cite the wrong bytes. Raises
  `ArgumentError` otherwise; a candidate that passes here is trusted when its
  span is copied at the end.
  """
  @spec candidates([Candidate.t()], String.t()) :: [Candidate.t()]
  def candidates(candidates, source) do
    Enum.each(candidates, &grounded(&1, source))
    dupes = for {id, n} <- Enum.frequencies_by(candidates, & &1.id), n > 1, do: id

    if dupes != [] do
      raise ArgumentError,
            "candidate ids must be unique, duplicated: #{inspect(Enum.sort(dupes))}"
    end

    candidates
  end

  @doc """
  One scan request: every atomic asked of every candidate in the window, over
  `extra_state` plus the window's candidates under `"candidates"`.
  """
  @spec request([Candidate.t()], [atomic()], map()) :: map()
  def request(window, atomics, extra_state) do
    questions =
      for %Candidate{} = candidate <- window, atomic <- atomics, into: %{} do
        {key(candidate.id, atomic.name), atomic.question.(candidate)}
      end

    state =
      extra_state
      |> Wire.map()
      |> Map.put("candidates", Wire.candidates(window))

    %{"state" => state, "questions" => Wire.questions(questions)}
  end

  @doc """
  Folds judged windows into the score index, one error per failed window, and
  the usage of each successful call.
  """
  @spec resolve([outcome()], [atomic()]) :: %{
          index: index(),
          errors: [Error.t()],
          usages: [Cite.usage() | nil],
          models: [String.t()]
        }
  def resolve(outcomes, atomics) do
    %{
      index: Enum.reduce(outcomes, %{}, &merge(&1, &2, atomics)),
      errors:
        for({window, {:error, reason}} <- outcomes, do: Error.from_candidates(window, reason)),
      usages: for({_window, {:ok, verdict}} <- outcomes, do: verdict.usage),
      models: for({_window, {:ok, %{model: model}}} <- outcomes, do: model)
    }
  end

  @doc """
  Keeps only the atomic scores above `threshold`; every candidate keeps its row.
  """
  @spec drop_below(index(), number()) :: index()
  def drop_below(index, threshold) do
    Map.new(index, fn {id, scores} ->
      kept = for {name, value} <- scores, value > threshold, into: %{}, do: {name, value}
      {id, kept}
    end)
  end

  defp atomic(%{name: name, question: question})
       when is_binary(name) and name != "" and is_function(question, 1),
       do: :ok

  defp atomic(other) do
    raise ArgumentError,
          "each atomic must be %{name: non-empty binary, question: fun/1}, got: #{inspect(other)}"
  end

  defp grounded(%Candidate{id: id, text: text, byte_start: start, byte_end: stop}, source)
       when is_integer(start) and is_integer(stop) and start >= 0 and stop >= start and
              stop <= byte_size(source) do
    text(id, text)

    case binary_part(source, start, stop - start) do
      ^text ->
        :ok

      slice ->
        raise ArgumentError, """
        candidate #{inspect(id)} text does not match source at [#{start}, #{stop}): \
        got #{inspect(slice)}, expected #{inspect(text)}
        """
    end
  end

  defp grounded(%Candidate{id: id, byte_start: start, byte_end: stop}, source) do
    raise ArgumentError, """
    candidate #{inspect(id)} has invalid offsets [#{inspect(start)}, #{inspect(stop)}) \
    for source of #{byte_size(source)} bytes
    """
  end

  defp grounded(other, _source) do
    raise ArgumentError, "expected a Candidate, got: #{inspect(other)}"
  end

  defp text(id, text) when is_binary(text) and text != "" do
    unless String.valid?(text) do
      raise ArgumentError, "candidate #{inspect(id)} text is not valid UTF-8: #{inspect(text)}"
    end
  end

  defp text(id, text) do
    raise ArgumentError,
          "candidate #{inspect(id)} text must be non-empty valid UTF-8, got: #{inspect(text)}"
  end

  defp merge({_window, {:error, _reason}}, index, _atomics), do: index

  defp merge({window, {:ok, %{answers: answers}}}, index, atomics) do
    Enum.reduce(window, index, fn %Candidate{id: id}, acc ->
      scores = Map.new(atomics, &{&1.name, Answer.noul(answers[key(id, &1.name)])})
      Map.update(acc, id, scores, &Map.merge(&1, scores))
    end)
  end

  defp key(id, atomic_name), do: id <> ":" <> to_string(atomic_name)
end
