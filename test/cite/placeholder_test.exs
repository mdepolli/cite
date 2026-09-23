defmodule Cite.PlaceholderTest do
  use ExUnit.Case, async: true

  alias Cite.Placeholder

  describe "names/1" do
    test "lists each placeholder once, in order of first use" do
      text = "Do {household} and {income} describe the same {household}?"

      assert Placeholder.names(text) == ["household", "income"]
    end

    test "is empty when the text has none" do
      assert Placeholder.names("How severe is it?") == []
    end
  end

  describe "expand/2" do
    test "replaces each placeholder with its backticked path" do
      text = "Does {passage} pose a riddle?"

      assert Placeholder.expand(text, %{"passage" => "utterances.U014.text"}) ==
               "Does `utterances.U014.text` pose a riddle?"
    end

    test "leaves text without placeholders untouched" do
      assert Placeholder.expand("How severe?", %{}) == "How severe?"
    end
  end

  describe "instructions/3" do
    test "one placeholder becomes inspect" do
      assert Placeholder.instructions("Does {passage} ...?", %{"passage" => "u.U1.text"}, []) ==
               %{"question" => "Does `u.U1.text` ...?", "inspect" => "`u.U1.text`"}
    end

    test "several placeholders become compare, in order of use" do
      paths = %{"household" => "household.text", "income" => "income.text"}

      assert Placeholder.instructions("Do {household} and {income} agree?", paths, []) == %{
               "question" => "Do `household.text` and `income.text` agree?",
               "compare" => ["`household.text`", "`income.text`"]
             }
    end

    test "none becomes compare over the fallback paths" do
      assert Placeholder.instructions("How severe?", %{}, ["u.U1.text", "u.U2.text"]) ==
               %{"question" => "How severe?", "compare" => ["`u.U1.text`", "`u.U2.text`"]}
    end
  end
end
