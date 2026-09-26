defmodule Cite.AnswerTest do
  use ExUnit.Case, async: true

  alias Cite.Answer

  describe "noul/1" do
    test "reads the noul value" do
      assert Answer.noul(%{"noul" => 0.73}) == 0.73
    end
  end

  describe "check/2" do
    @score %{"type" => "score", "criteria" => ["low", "medium", "high"]}
    @choice %{"type" => "choice", "criteria" => %{"transient" => "t", "persistent" => "p"}}

    @questions %{
      "P0:riddle" => %{"type" => "noul"},
      "severity" => @score,
      "temporal" => @choice
    }

    test "accepts one well-formed answer per question" do
      answers = %{
        "P0:riddle" => %{"noul" => 0.9},
        "severity" => %{"score" => 1.2, "confidence" => 0.8},
        "temporal" => %{"choice" => "persistent", "confidence" => 0.9}
      }

      assert Answer.check(@questions, answers) == :ok
    end

    test "names every question left unanswered, sorted" do
      answers = %{"severity" => %{"score" => 1.2, "confidence" => 0.8}}

      assert Answer.check(@questions, answers) ==
               {:error, {:missing_answers, ["P0:riddle", "temporal"]}}
    end

    test "names every answer in a shape its type cannot have, sorted" do
      answers = %{
        "P0:riddle" => %{"noul" => "high"},
        "severity" => %{"score" => 1.2},
        "temporal" => %{"choice" => "persistent", "confidence" => 0.9}
      }

      assert Answer.check(@questions, answers) ==
               {:error, {:malformed_answers, ["P0:riddle", "severity"]}}
    end

    test "rejects every answer shape its question type cannot have" do
      for {question, answer} <- [
            {%{"type" => "noul"}, %{"noul" => "high"}},
            {%{"type" => "noul"}, %{}},
            {%{"type" => "noul"}, nil},
            {%{"type" => "noul"}, %{"score" => 1, "confidence" => 0.9}},
            {@score, %{"score" => 1.2}},
            {@choice, %{"choice" => "transient"}},
            {@choice, %{"choice" => 1, "confidence" => 0.9}}
          ] do
        assert Answer.check(%{"q" => question}, %{"q" => answer}) ==
                 {:error, {:malformed_answers, ["q"]}}
      end
    end

    test "rejects every value its question cannot have" do
      for {question, answer} <- [
            {%{"type" => "noul"}, %{"noul" => 7}},
            {%{"type" => "noul"}, %{"noul" => -0.1}},
            {@score, %{"score" => 2.5, "confidence" => 0.8}},
            {@score, %{"score" => -1, "confidence" => 0.8}},
            {@score, %{"score" => 1, "confidence" => 1.5}},
            {@choice, %{"choice" => "forever", "confidence" => 0.9}},
            {@choice, %{"choice" => "transient", "confidence" => -0.2}}
          ] do
        assert Answer.check(%{"q" => question}, %{"q" => answer}) ==
                 {:error, {:malformed_answers, ["q"]}}
      end
    end

    test "accepts the bounds of every range" do
      for {question, answer} <- [
            {%{"type" => "noul"}, %{"noul" => 0}},
            {%{"type" => "noul"}, %{"noul" => 1.0}},
            {@score, %{"score" => 0, "confidence" => 0}},
            {@score, %{"score" => 2, "confidence" => 1}}
          ] do
        assert Answer.check(%{"q" => question}, %{"q" => answer}) == :ok
      end
    end

    test "ignores answers to questions it did not ask" do
      answers = %{
        "P0:riddle" => %{"noul" => 0.9},
        "severity" => %{"score" => 1.2, "confidence" => 0.8},
        "temporal" => %{"choice" => "persistent", "confidence" => 0.9},
        "P1:riddle" => %{"noul" => "anything"}
      }

      assert Answer.check(@questions, answers) == :ok
    end

    test "reports missing answers before malformed ones" do
      answers = %{"P0:riddle" => %{"noul" => "high"}}

      assert Answer.check(@questions, answers) ==
               {:error, {:missing_answers, ["severity", "temporal"]}}
    end
  end
end
