defmodule Cite.WireTest do
  use ExUnit.Case, async: true

  alias Cite.{Candidate, Passage, Question, Wire}
  alias Cite.Policy.Question, as: PolicyQuestion
  alias Cite.Wire.Object

  describe "passages/2" do
    test "keys passages by id in source order, with only the shown meta" do
      # Arrange
      passages = [
        %Passage{
          id: "U014",
          text: "behind on the mortgage",
          meta: %{speaker: "B", start: 81_230}
        },
        %Passage{id: "U015", text: "the cashflow chart", meta: %{speaker: "A"}}
      ]

      # Act
      object = Wire.passages(passages, [:speaker])

      # Assert
      assert object == %Object{
               pairs: [
                 {"U014",
                  %{"id" => "U014", "speaker" => "B", "text" => "behind on the mortgage"}},
                 {"U015", %{"id" => "U015", "speaker" => "A", "text" => "the cashflow chart"}}
               ]
             }
    end

    test "sends no meta when show is empty" do
      object = Wire.passages([%Passage{id: "P0", text: "a", meta: %{speaker: "B"}}], [])

      assert object == %Object{pairs: [{"P0", %{"id" => "P0", "text" => "a"}}]}
    end

    test "matches show keys exactly as given" do
      passages = [%Passage{id: "P0", text: "a", meta: %{"speaker" => "B", "role" => "client"}}]

      assert Wire.passages(passages, [:speaker, "role"]) ==
               %Object{pairs: [{"P0", %{"id" => "P0", "text" => "a", "role" => "client"}}]}
    end
  end

  describe "passage/2" do
    test "wires one passage with its shown meta" do
      passage = %Passage{id: "U003", text: "two kids", meta: %{speaker: "B", start: 9}}

      assert Wire.passage(passage, [:speaker]) ==
               %{"id" => "U003", "speaker" => "B", "text" => "two kids"}
    end
  end

  describe "question/3" do
    test "encodes a Noul with its placeholder path and structured criteria" do
      # Arrange
      question = %PolicyQuestion{
        type: :noul,
        text: "Does {passage} say money is short?",
        focus: nil,
        criteria: %{
          true: %{what: "Short now.", examples: ["behind"]},
          false: %{what: "No strain.", not_for: "Bills as facts."}
        }
      }

      # Act
      wired = Wire.question(question, %{"passage" => "utterances.U014.text"}, [])

      # Assert
      assert wired == %{
               "type" => "noul",
               "instructions" => %{
                 "question" => "Does `utterances.U014.text` say money is short?",
                 "inspect" => "`utterances.U014.text`"
               },
               "criteria" => %{
                 "true" => %{"what" => "Short now.", "examples" => ["behind"]},
                 "false" => %{"what" => "No strain.", "not_for" => "Bills as facts."}
               }
             }
    end

    test "encodes a Score with its focus and compare over the fallback paths" do
      question = %PolicyQuestion{
        type: :score,
        text: "How bad?",
        focus: "Judge impact.",
        criteria: ["a", "b"]
      }

      assert Wire.question(question, %{}, ["household.text", "income.text"]) == %{
               "type" => "score",
               "instructions" => %{
                 "question" => "How bad?",
                 "focus" => "Judge impact.",
                 "compare" => ["`household.text`", "`income.text`"]
               },
               "criteria" => ["a", "b"]
             }
    end

    test "encodes a Choice and expands placeholders in its focus" do
      question = %PolicyQuestion{
        type: :choice,
        text: "Is {passage} temporary?",
        focus: "Read {passage} only.",
        criteria: %{"transient" => "recovers", "persistent" => "lasting"}
      }

      assert Wire.question(question, %{"passage" => "p.P0.text"}, []) == %{
               "type" => "choice",
               "instructions" => %{
                 "question" => "Is `p.P0.text` temporary?",
                 "focus" => "Read `p.P0.text` only.",
                 "inspect" => "`p.P0.text`"
               },
               "criteria" => %{"transient" => "recovers", "persistent" => "lasting"}
             }
    end
  end

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

  describe "map/1 rejects what it cannot send" do
    test "an unknown struct anywhere in the tree" do
      assert_raise ArgumentError, ~r/got a URI struct/, fn ->
        Wire.map(%{"when" => %{"at" => URI.parse("x")}})
      end
    end

    test "a candidate list with a non-candidate in it" do
      c = %Candidate{id: "C0", text: "a", byte_start: 0, byte_end: 1}

      assert_raise ArgumentError, ~r/expected a Cite.Candidate in state, got: :x/, fn ->
        Wire.map(%{"lines" => [c, :x]})
      end
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
