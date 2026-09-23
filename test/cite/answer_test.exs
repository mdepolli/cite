defmodule Cite.AnswerTest do
  use ExUnit.Case, async: true

  alias Cite.Answer

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
end
