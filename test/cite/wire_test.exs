defmodule Cite.WireTest do
  use ExUnit.Case, async: true

  alias Cite.{Passage, Wire}
  alias Cite.Policy.Question
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
      # Act
      object = Wire.passages([%Passage{id: "P0", text: "a", meta: %{speaker: "B"}}], [])

      # Assert
      assert object == %Object{pairs: [{"P0", %{"id" => "P0", "text" => "a"}}]}
    end

    test "matches show keys exactly as given" do
      # Arrange
      passages = [%Passage{id: "P0", text: "a", meta: %{"speaker" => "B", "role" => "client"}}]

      # Act + Assert
      assert Wire.passages(passages, [:speaker, "role"]) ==
               %Object{pairs: [{"P0", %{"id" => "P0", "text" => "a", "role" => "client"}}]}
    end
  end

  describe "passage/2" do
    test "wires one passage with its shown meta" do
      # Arrange
      passage = %Passage{id: "U003", text: "two kids", meta: %{speaker: "B", start: 9}}

      # Act + Assert
      assert Wire.passage(passage, [:speaker]) ==
               %{"id" => "U003", "speaker" => "B", "text" => "two kids"}
    end
  end

  describe "question/3" do
    test "encodes a Noul with its placeholder path and structured criteria" do
      # Arrange
      question = %Question{
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
      # Arrange
      question = %Question{
        type: :score,
        text: "How bad?",
        focus: "Judge impact.",
        criteria: ["a", "b"]
      }

      # Act + Assert
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
      # Arrange
      question = %Question{
        type: :choice,
        text: "Is {passage} temporary?",
        focus: "Read {passage} only.",
        criteria: %{"transient" => "recovers", "persistent" => "lasting"}
      }

      # Act + Assert
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

  describe "shown meta" do
    test "stringifies nested keys and leaves binary keys alone" do
      # Arrange
      passage = %Passage{id: "U1", text: "a", meta: %{about: %{"role" => [%{kind: :client}]}}}

      # Act + Assert
      assert Wire.passage(passage, [:about]) == %{
               "id" => "U1",
               "text" => "a",
               "about" => %{"role" => [%{"kind" => :client}]}
             }
    end
  end

  test "passages keep source order on the wire past 32 entries" do
    # Arrange: 40 passages; a plain map of these encodes in hash order.
    passages = for i <- 0..39, do: %Passage{id: id(i), text: "t#{i}"}

    # Act
    json = Jason.encode!(Wire.passages(passages, []))

    # Assert
    assert wire_keys(json) == [
             "U000",
             "U001",
             "U002",
             "U003",
             "U004",
             "U005",
             "U006",
             "U007",
             "U008",
             "U009",
             "U010",
             "U011",
             "U012",
             "U013",
             "U014",
             "U015",
             "U016",
             "U017",
             "U018",
             "U019",
             "U020",
             "U021",
             "U022",
             "U023",
             "U024",
             "U025",
             "U026",
             "U027",
             "U028",
             "U029",
             "U030",
             "U031",
             "U032",
             "U033",
             "U034",
             "U035",
             "U036",
             "U037",
             "U038",
             "U039"
           ]
  end

  defp id(i), do: "U" <> String.pad_leading(Integer.to_string(i), 3, "0")

  # Top-level key order as it appears in the JSON text.
  defp wire_keys(json) do
    ~r/"(U\d{3})":\{/
    |> Regex.scan(json)
    |> Enum.map(fn [_, key] -> key end)
  end
end
