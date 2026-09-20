defmodule Cite.WireTest do
  use ExUnit.Case, async: true

  alias Cite.{Candidate, Question, Wire}

  describe "map/1" do
    test "stringifies atom keys recursively and leaves binary keys alone" do
      assert Wire.map(%{"b" => %{c: [%{d: 2}]}, a: 1}) == %{
               "a" => 1,
               "b" => %{"c" => [%{"d" => 2}]}
             }
    end

    test "wires a candidate found anywhere in the tree" do
      # Arrange
      candidate = %Candidate{
        id: "U007",
        text: "hi",
        byte_start: 0,
        byte_end: 2,
        meta: %{speaker: "A"}
      }

      # Act
      wired = Wire.map(%{"household" => candidate, nested: %{list: [candidate]}})

      # Assert
      expected = %{"id" => "U007", "text" => "hi", "speaker" => "A"}
      assert wired == %{"household" => expected, "nested" => %{"list" => [expected]}}
    end
  end

  describe "candidate/1" do
    test "is meta plus id and text, with text winning over a meta key" do
      candidate = %Candidate{
        id: "U1",
        text: "real",
        byte_start: 0,
        byte_end: 4,
        meta: %{text: "meta"}
      }

      assert Wire.candidate(candidate) == %{"id" => "U1", "text" => "real"}
    end
  end

  describe "questions/1" do
    test "encodes every question under its key" do
      # Arrange
      question = Question.noul(question: "Q?", inspect: "`x`", true: "yes", false: "no")

      # Act
      wired = Wire.questions(%{"fits" => question})

      # Assert
      assert %{"fits" => %{"type" => "noul", "instructions" => %{"question" => "Q?"}}} = wired
    end
  end
end
