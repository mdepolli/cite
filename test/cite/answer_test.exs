defmodule Cite.AnswerTest do
  use ExUnit.Case, async: true

  alias Cite.{Answer, Question}

  defp score_q,
    do: Question.score(question: "How bad?", inspect: "`x`", criteria: ["a", "b", "c"])

  defp choice_q,
    do: Question.choice(question: "Which?", inspect: "`x`", criteria: %{"t" => "x", "p" => "y"})

  defp noul_q, do: Question.noul(question: "Q?", inspect: "`x`", true: "yes", false: "no")

  describe "noul/1" do
    test "reads the noul value" do
      assert Answer.noul(%{"noul" => 0.73}) == 0.73
    end

    test "reads missing or malformed answers as 0.0" do
      assert Answer.noul(nil) == 0.0
      assert Answer.noul(%{"noul" => "high"}) == 0.0
      assert Answer.noul(%{"score" => 1}) == 0.0
    end
  end

  describe "label/3" do
    test "rounds a confident score to its level" do
      assert Answer.label(score_q(), %{"score" => 1.4, "confidence" => 0.9}, 0.5) == 1
      assert Answer.label(score_q(), %{"score" => 1.6, "confidence" => 0.9}, 0.5) == 2
    end

    test "labels a score uncertain below the floor" do
      assert Answer.label(score_q(), %{"score" => 1.0, "confidence" => 0.3}, 0.5) == "uncertain"
    end

    test "returns a confident choice" do
      assert Answer.label(choice_q(), %{"choice" => "t", "confidence" => 0.8}, 0.5) == "t"
    end

    test "labels a choice uncertain below the floor" do
      assert Answer.label(choice_q(), %{"choice" => "t", "confidence" => 0.2}, 0.5) == "uncertain"
    end

    test "is nil for nouls and for missing answers" do
      assert Answer.label(noul_q(), %{"noul" => 0.9}, 0.5) == nil
      assert Answer.label(score_q(), nil, 0.5) == nil
      assert Answer.label(choice_q(), %{}, 0.5) == nil
    end
  end
end
