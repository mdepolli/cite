defmodule Cite.ScreenTest do
  use ExUnit.Case, async: true

  alias Cite.{Policy, Screen, Source}
  alias Cite.TestPolicies.{Household, Riddles}
  alias Cite.Wire.Object

  describe "indicators/1" do
    test "lists filters, then directly screened concerns, then factors" do
      assert Keyword.keys(Screen.indicators(Policy.compiled(Household))) == [
               :client_speaking,
               :cashflow_stress,
               :dependents,
               :primary_income,
               :other_household_income
             ]
    end
  end

  describe "request/3" do
    test "asks every indicator of every passage in the window, under the source's word" do
      # Arrange
      source =
        Source.new(
          [
            %{
              id: "L1",
              text: "Why is a raven like a writing-desk?",
              meta: %{speaker: "Hatter", at: 1}
            },
            %{id: "L2", text: "Take some more tea.", meta: %{speaker: "Hare"}}
          ],
          as: "lines",
          show: [:speaker]
        )

      # Act
      request = Screen.request(source.passages, source, Policy.compiled(Riddles))

      # Assert
      criteria = %{
        "true" => %{"what" => "A question asked to be puzzled over."},
        "false" => %{"what" => "A plain question, a statement, or a remark."}
      }

      assert request == %{
               "state" => %{
                 "lines" =>
                   Object.new([
                     {"L1",
                      %{
                        "id" => "L1",
                        "speaker" => "Hatter",
                        "text" => "Why is a raven like a writing-desk?"
                      }},
                     {"L2", %{"id" => "L2", "speaker" => "Hare", "text" => "Take some more tea."}}
                   ])
               },
               "questions" => %{
                 "L1:riddle" => %{
                   "type" => "noul",
                   "instructions" => %{
                     "question" => "Does `lines.L1.text` pose a riddle?",
                     "inspect" => "`lines.L1.text`"
                   },
                   "criteria" => criteria
                 },
                 "L2:riddle" => %{
                   "type" => "noul",
                   "instructions" => %{
                     "question" => "Does `lines.L2.text` pose a riddle?",
                     "inspect" => "`lines.L2.text`"
                   },
                   "criteria" => criteria
                 }
               }
             }
    end

    test "asks each of a full policy's indicators once per passage" do
      source = Source.new([%{id: "U3", text: "Two kids."}], as: "utterances")

      %{"questions" => questions} =
        Screen.request(source.passages, source, Policy.compiled(Household))

      assert Enum.sort(Map.keys(questions)) == [
               "U3:cashflow_stress",
               "U3:client_speaking",
               "U3:dependents",
               "U3:other_household_income",
               "U3:primary_income"
             ]
    end
  end

  describe "resolve/2" do
    test "folds answers into scores per passage and indicator" do
      # Arrange
      source = Source.new([%{id: "L1", text: "a"}, %{id: "L2", text: "b"}])

      verdict = %{
        answers: %{"L1:riddle" => %{"noul" => 0.94}, "L2:riddle" => %{"noul" => 0.03}},
        usage: %{input_tokens: 10, output_tokens: 0},
        model: "jev-1.13.0"
      }

      # Act
      resolved = Screen.resolve([{source.passages, {:ok, verdict}}], Policy.compiled(Riddles))

      # Assert
      assert resolved == %{
               screen: %{"L1" => %{riddle: 0.94}, "L2" => %{riddle: 0.03}},
               errors: [],
               usages: [%{input_tokens: 10, output_tokens: 0}],
               models: ["jev-1.13.0"]
             }
    end

    test "a failed window leaves no rows and records one error with its passage ids" do
      source = Source.new([%{id: "L1", text: "a"}, %{id: "L2", text: "b"}])

      resolved = Screen.resolve([{source.passages, {:error, :timeout}}], Policy.compiled(Riddles))

      assert resolved == %{
               screen: %{},
               errors: [{["L1", "L2"], :timeout}],
               usages: [],
               models: []
             }
    end
  end
end
