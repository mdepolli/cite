defmodule Cite.Answer do
  @moduledoc """
  Reply maps to values.

  Knows what an answer to each question type may be, and nothing else.
  Every answer that reaches `noul/1` has passed `check/2`; a reply that
  fails it is an error for its whole request, never a value. Internal.
  """

  @doc """
  Checks a reply against the questions it answers, as they went on the wire:
  `:ok` when every question has one well-formed answer, otherwise
  `{:error, {:missing_answers, keys}}` or
  `{:error, {:malformed_answers, keys}}`, keys sorted, missing first. A
  reply that fails is an error for its whole request, never a "no".
  """
  @spec check(%{String.t() => map()}, map()) ::
          :ok | {:error, {:missing_answers | :malformed_answers, [String.t()]}}
  def check(questions, answers) when is_map(questions) and is_map(answers) do
    missing = Map.keys(questions) -- Map.keys(answers)

    malformed =
      for {key, question} <- questions,
          Map.has_key?(answers, key),
          not well_formed?(question, answers[key]),
          do: key

    cond do
      missing != [] -> {:error, {:missing_answers, Enum.sort(missing)}}
      malformed != [] -> {:error, {:malformed_answers, Enum.sort(malformed)}}
      true -> :ok
    end
  end

  # One well-formed answer: a "noul" probability; a "score" that is a level
  # index, from 0 to the last level; a "choice" that is one of the options.
  # Every confidence is a probability. A score may fall between levels.
  defp well_formed?(%{"type" => "noul"}, %{"noul" => p}), do: probability?(p)

  defp well_formed?(%{"type" => "score", "criteria" => levels}, %{"score" => s} = answer) do
    is_number(s) and s >= 0 and s <= length(levels) - 1 and probability?(answer["confidence"])
  end

  defp well_formed?(%{"type" => "choice", "criteria" => options}, %{"choice" => o} = answer) do
    Map.has_key?(options, o) and probability?(answer["confidence"])
  end

  defp well_formed?(_question, _answer), do: false

  defp probability?(p), do: is_number(p) and p >= 0 and p <= 1

  @doc "The Noul probability of a well-formed Noul answer."
  @spec noul(map()) :: number()
  def noul(%{"noul" => value}), do: value
end
