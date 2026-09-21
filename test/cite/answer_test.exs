defmodule Cite.AnswerTest do
  use ExUnit.Case, async: true

  alias Cite.{Answer, Question}

  defp score_q,
    do: Question.score(question: "How bad?", inspect: "`x`", criteria: ["a", "b", "c"])

  defp choice_q,
    do: Question.choice(question: "Which?", inspect: "`x`", criteria: %{"t" => "x", "p" => "y"})

  defp noul_q, do: Question.noul(question: "Q?", inspect: "`x`", true: "yes", false: "no")

  describe "well_formed?/2" do
    test "accepts each type's shape and nothing else" do
      assert Answer.well_formed?("noul", %{"noul" => 0.7})
      assert Answer.well_formed?("score", %{"score" => 1.2, "confidence" => 0.9})
      assert Answer.well_formed?("choice", %{"choice" => "t", "confidence" => 0.9})

      refute Answer.well_formed?("noul", %{"noul" => "high"})
      refute Answer.well_formed?("noul", %{})
      refute Answer.well_formed?("noul", nil)
      refute Answer.well_formed?("score", %{"score" => 1.2})
      refute Answer.well_formed?("choice", %{"choice" => "t"})
      refute Answer.well_formed?("choice", %{"choice" => 1, "confidence" => 0.9})
      refute Answer.well_formed?("noul", %{"score" => 1, "confidence" => 0.9})
    end
  end

  describe "noul/1" do
    test "reads the noul value" do
      assert Answer.noul(%{"noul" => 0.73}) == 0.73
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

    test "is nil for nouls" do
      assert Answer.label(noul_q(), %{"noul" => 0.9}, 0.5) == nil
    end
  end
end
