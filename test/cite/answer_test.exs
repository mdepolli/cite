defmodule Cite.AnswerTest do
  use ExUnit.Case, async: true

  alias Cite.Answer

  describe "noul/1" do
    test "reads the noul value" do
      assert Answer.noul(%{"noul" => 0.73}) == 0.73
    end
  end

  describe "check/2" do
    @questions %{
      "P0:riddle" => %{"type" => "noul"},
      "severity" => %{"type" => "score"},
      "temporal" => %{"type" => "choice"}
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
      for {type, answer} <- [
            {"noul", %{"noul" => "high"}},
            {"noul", %{}},
            {"noul", nil},
            {"noul", %{"score" => 1, "confidence" => 0.9}},
            {"score", %{"score" => 1.2}},
            {"choice", %{"choice" => "t"}},
            {"choice", %{"choice" => 1, "confidence" => 0.9}}
          ] do
        assert Answer.check(%{"q" => %{"type" => type}}, %{"q" => answer}) ==
                 {:error, {:malformed_answers, ["q"]}}
      end
    end

    test "reports missing answers before malformed ones" do
      answers = %{"P0:riddle" => %{"noul" => "high"}}

      assert Answer.check(@questions, answers) ==
               {:error, {:missing_answers, ["severity", "temporal"]}}
    end
  end
end
