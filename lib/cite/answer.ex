defmodule Cite.Answer do
  # Judge reply maps → values. Reads one answer at a time; knows the reply
  # shape for each question type and nothing else.
  @moduledoc false

  alias Cite.Question

  @doc """
  The Noul probability of an answer.

  Missing or malformed answers read as `0.0` — a confident "no". Same as the
  prototype: an unanswered key is not distinguished from a negative Noul.
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
