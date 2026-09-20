defmodule Cite.WireTest do
  use ExUnit.Case, async: true

  alias Cite.{Candidate, Question, Wire}
  alias Cite.Wire.Object

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
      wired = Wire.map(%{"household" => candidate, nested: %{list: [1, candidate]}})

      # Assert
      expected = %{"id" => "U007", "text" => "hi", "speaker" => "A"}
      assert wired == %{"household" => expected, "nested" => %{"list" => [1, expected]}}
    end
  end

  describe "map/1 keys" do
    test "raises on a key that is neither atom nor binary" do
      assert_raise ArgumentError, ~r/keys must be atoms or binaries, got: 1/, fn ->
        Wire.map(%{1 => "x"})
      end
    end
  end

  describe "candidates/1" do
    test "keeps window order on the wire past 32 entries, under both encoders" do
      # Arrange — 40 candidates; a plain map of these encodes in hash order.
      candidates =
        for i <- 0..39 do
          id = "U" <> String.pad_leading(Integer.to_string(i), 3, "0")
          %Candidate{id: id, text: "t#{i}", byte_start: 0, byte_end: 1}
        end

      ids = Enum.map(candidates, & &1.id)

      # Act
      object = Wire.candidates(candidates)

      # Assert
      assert object["U039"] == %{"id" => "U039", "text" => "t39"}
      assert wire_keys(Jason.encode!(object)) == ids
      assert JSON.encode!(object) == Jason.encode!(object)
      refute wire_keys(Jason.encode!(Map.new(object.pairs))) == ids
    end

    test "a list of candidates inside state is wired the same way" do
      c0 = %Candidate{id: "C000", text: "a", byte_start: 0, byte_end: 1}
      c5 = %Candidate{id: "C005", text: "b", byte_start: 2, byte_end: 3}

      assert %{"lines" => %Object{pairs: [{"C000", _}, {"C005", _}]}} =
               Wire.map(%{"lines" => [c0, c5]})
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

  # Top-level key order as it appears in the JSON text.
  defp wire_keys(json) do
    Regex.scan(~r/"(U\d{3})":\{/, json) |> Enum.map(fn [_, key] -> key end)
  end
end
