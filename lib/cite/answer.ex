defmodule Cite.Answer do
  @moduledoc """
  Reply maps to values.

  Reads one answer at a time and knows the reply shape of each question
  type — the Noul probability, the Score level, the Choice option — and
  nothing else. Internal.
  """

  alias Cite.Question

  @doc """
  The Noul probability of an answer.

  A malformed answer reads as `0.0`. A *missing* answer never reaches here:
  the shell records a reply that skips a question as an error for that
  request.
  """
  @spec noul(term()) :: number()
  def noul(%{"noul" => value}) when is_number(value), do: value
  def noul(_), do: 0.0

  @doc """
  The label an answer earns under its question type, or `nil` when the type
  yields no label (Nouls) or the answer is missing.

  A Score labels as `round(score)`; a Choice as its `choice`. Either becomes
  `"uncertain"` when `confidence` is below `floor`.
  """
  @spec label(Question.t(), term(), number()) :: integer() | String.t() | nil
  def label(%Question{type: :score}, %{"score" => score, "confidence" => confidence}, floor)
      when is_number(score) and is_number(confidence) and confidence >= floor do
    round(score)
  end

  def label(%Question{type: :score}, %{"score" => _}, _floor), do: "uncertain"
  def label(%Question{type: :score}, _, _floor), do: nil

  def label(%Question{type: :choice}, %{"choice" => choice, "confidence" => confidence}, floor)
      when is_number(confidence) and confidence >= floor do
    choice
  end

  def label(%Question{type: :choice}, %{"choice" => _}, _floor), do: "uncertain"
  def label(%Question{type: :choice}, _, _floor), do: nil

  def label(%Question{type: :noul}, _, _floor), do: nil
end
