defmodule Cite.Answer do
  @moduledoc """
  Reply maps to values.

  Knows the reply shape of each question type and nothing else. Every
  answer that reaches `noul/1` has passed `well_formed?/2` in the shell; a
  reply that fails it is an error for its whole request, never a value.
  Internal.
  """

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
end
