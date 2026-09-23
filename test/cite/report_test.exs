defmodule Cite.ReportTest do
  use ExUnit.Case, async: true

  alias Cite.{Report, TestRun, TestTerms}

  describe "new/1" do
    test "reports a judged run, usage totalled and models listed once" do
      # Arrange
      run =
        TestRun.new(TestTerms.riddles(),
          screen: %{"P000" => %{riddle: 0.1}},
          findings: [],
          usages: [
            %{input_tokens: 10, output_tokens: 2},
            nil,
            %{input_tokens: 5, output_tokens: 1}
          ],
          models: ["jev-1.13.0", "jev-1.13.0"]
        )

      # Act
      report = Report.new(run)

      # Assert
      assert report == %Report{
               findings: [],
               screen: %{"P000" => %{riddle: 0.1}},
               errors: [],
               usage: %{input_tokens: 15, output_tokens: 3},
               models: ["jev-1.13.0"]
             }
    end

    test "refuses a run that has not been judged" do
      assert_raise FunctionClauseError, fn ->
        Report.new(TestRun.new(TestTerms.riddles(), screen: %{}))
      end
    end
  end
end
