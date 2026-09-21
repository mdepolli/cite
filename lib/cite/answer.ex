defmodule Cite.Answer do
  @moduledoc """
  Reply maps to values.

  Reads one answer at a time and knows the reply shape of each question
  type — the Noul probability, the Score level, the Choice option — and
  nothing else. Every answer that reaches `noul/1` or `label/3` has passed
  `well_formed?/2` in the shell; a reply that fails it is an error for its
  whole request, never a value. Internal.
  """

  alias Cite.Question

  @doc """
  Whether an answer has the shape its question type promises: a numeric
  `"noul"`; a numeric `"score"` with a numeric `"confidence"`; a binary
  `"choice"` with a numeric `"confidence"`. `type` is the wire type string.
  """
  @spec well_formed?(String.t(), term()) :: boolean()
  def well_formed?("noul", %{"noul" => p}) when is_number(p), do: true

  def well_formed?("score", %{"score" => s, "confidence" => c})
      when is_number(s) and is_number(c),
      do: true

  def well_formed?("choice", %{"choice" => o, "confidence" => c})
      when is_binary(o) and is_number(c),
      do: true

  def well_formed?(_type, _answer), do: false

  @doc "The Noul probability of a well-formed Noul answer."
  @spec noul(map()) :: number()
  def noul(%{"noul" => value}), do: value

  @doc """
  The label a well-formed answer earns under its question type, or `nil` for
  a Noul, which labels nothing.

  A Score labels as `round(score)`; a Choice as its `choice`. Either becomes
  `"uncertain"` when `confidence` is below `floor`.
  """
  @spec label(Question.t(), map(), number()) :: integer() | String.t() | nil
  def label(%Question{type: :score}, %{"score" => score, "confidence" => confidence}, floor) do
    if confidence >= floor, do: round(score), else: "uncertain"
  end

  def label(%Question{type: :choice}, %{"choice" => choice, "confidence" => confidence}, floor) do
    if confidence >= floor, do: choice, else: "uncertain"
  end

  def label(%Question{type: :noul}, _answer, _floor), do: nil
end
