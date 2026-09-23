defmodule Cite.Answer do
  @moduledoc """
  Reply maps to values.

  Knows the reply shape of each question type and nothing else. Every
  answer that reaches `noul/1` has passed `check/2`; a reply that fails it
  is an error for its whole request, never a value. Internal.
  """

  @doc """
  Checks a reply against the questions it answers: `:ok` when every question
  has one well-formed answer, otherwise `{:error, {:missing_answers, keys}}`
  or `{:error, {:malformed_answers, keys}}`, keys sorted, missing first. A
  reply that fails is an error for its whole request, never a "no".
  """
  @spec check(%{String.t() => map()}, map()) ::
          :ok | {:error, {:missing_answers | :malformed_answers, [String.t()]}}
  def check(questions, answers) when is_map(questions) and is_map(answers) do
    missing = Map.keys(questions) -- Map.keys(answers)

    malformed =
      for {key, question} <- questions,
          Map.has_key?(answers, key),
          not well_formed?(question["type"], answers[key]),
          do: key

    cond do
      missing != [] -> {:error, {:missing_answers, Enum.sort(missing)}}
      malformed != [] -> {:error, {:malformed_answers, Enum.sort(malformed)}}
      true -> :ok
    end
  end

  # One well-formed answer: a numeric "noul"; a numeric "score" with a numeric
  # "confidence"; a binary "choice" with a numeric "confidence". `type` is the
  # wire type string.
  defp well_formed?("noul", %{"noul" => p}) when is_number(p), do: true

  defp well_formed?("score", %{"score" => s, "confidence" => c})
       when is_number(s) and is_number(c),
       do: true

  defp well_formed?("choice", %{"choice" => o, "confidence" => c})
       when is_binary(o) and is_number(c),
       do: true

  defp well_formed?(_type, _answer), do: false

  @doc "The Noul probability of a well-formed Noul answer."
  @spec noul(map()) :: number()
  def noul(%{"noul" => value}), do: value
end
