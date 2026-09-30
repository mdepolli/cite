defmodule Cite.ScreenTest do
  use ExUnit.Case, async: true

  alias Cite.{Error, Screen, Source, TestRun, TestTerms}
  alias Cite.Wire.Object

  describe "request/2" do
    test "asks every detect of every passage in the window, under the source's word" do
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

      request = Screen.request(TestRun.new(TestTerms.riddles(), source: source), source.passages)

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

    test "asks each of a full policy's detects once per passage" do
      source = Source.new([%{id: "U3", text: "Two kids."}], as: "utterances")

      %{"questions" => questions} =
        Screen.request(TestRun.new(TestTerms.household(), source: source), source.passages)

      assert Enum.sort(Map.keys(questions)) == [
               "U3:cashflow_stress",
               "U3:client_speaking",
               "U3:dependents",
               "U3:other_household_income",
               "U3:primary_income"
             ]
    end

    test "asks a factor two concerns share once per passage" do
      source = Source.new([%{id: "U3", text: "Two kids."}], as: "utterances")

      %{"questions" => questions} =
        Screen.request(TestRun.new(TestTerms.shared_factor(), source: source), source.passages)

      assert Map.keys(questions) == ["U3:dependents"]
    end
  end

  describe "resolve/2" do
    test "folds answers into scores per passage and detect" do
      source = Source.new([%{id: "L1", text: "a"}, %{id: "L2", text: "b"}])

      verdict = %{
        answers: %{"L1:riddle" => %{"noul" => 0.94}, "L2:riddle" => %{"noul" => 0.03}},
        usage: %{input_tokens: 10, output_tokens: 0},
        model: "jev-1.13.0"
      }

      run = Screen.resolve(TestRun.new(TestTerms.riddles()), [{source.passages, {:ok, verdict}}])

      assert {run.screen, run.errors, run.usages, run.models} ==
               {%{"L1" => %{riddle: 0.94}, "L2" => %{riddle: 0.03}}, [],
                [%{input_tokens: 10, output_tokens: 0}], ["jev-1.13.0"]}
    end

    test "a failed window leaves no rows and records one error with its passage ids" do
      source = Source.new([%{id: "L1", text: "a"}, %{id: "L2", text: "b"}])

      run =
        Screen.resolve(TestRun.new(TestTerms.riddles()), [{source.passages, {:error, :timeout}}])

      assert {run.screen, run.errors, run.usages, run.models} ==
               {%{}, [%Error{concern: nil, passage_ids: ["L1", "L2"], reason: :timeout}], [], []}
    end

    test "adds its errors, usages, and models to those the run already holds" do
      run =
        TestRun.new(TestTerms.riddles(),
          errors: [%Error{concern: nil, passage_ids: ["L0"], reason: :timeout}],
          usages: [nil],
          models: ["jev-1.12.0"]
        )

      verdict = %{answers: %{"L1:riddle" => %{"noul" => 0.9}}, usage: nil, model: "jev-1.13.0"}
      [l1, l2] = Source.new([%{id: "L1", text: "a"}, %{id: "L2", text: "b"}]).passages
      run = Screen.resolve(run, [{[l1], {:ok, verdict}}, {[l2], {:error, :timeout}}])

      assert {run.errors, run.usages, run.models} ==
               {[
                  %Error{concern: nil, passage_ids: ["L0"], reason: :timeout},
                  %Error{concern: nil, passage_ids: ["L2"], reason: :timeout}
                ], [nil, nil], ["jev-1.12.0", "jev-1.13.0"]}
    end
  end
end
