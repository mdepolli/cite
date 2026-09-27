defmodule Cite.ReadmeTest do
  use ExUnit.Case, async: true

  alias Cite.{Finding, Report}

  # The Quick start is a program. Its client line needs a key, so the test
  # drops that line and injects a stub; the rest runs as written.
  test "the Quick start example runs and cites the riddle" do
    # Arrange
    example = quick_start_code()

    client = fn %{"questions" => questions} ->
      answers =
        Map.new(questions, fn {key, _question} ->
          {key, %{"noul" => if(String.contains?(key, "P000"), do: 0.9, else: 0.1)}}
        end)

      {:ok, %{answers: answers, usage: nil}}
    end

    # Act
    {report, _binding} = Code.eval_string(example, client: client)

    # Assert
    assert %Report{findings: [%Finding{concern: :riddle, verdict: :holds} = finding]} = report

    assert Enum.map(finding.evidence, & &1.passage.text) == [
             "Why is a raven like a writing-desk?"
           ]
  end

  defp quick_start_code do
    readme = File.read!("README.md")
    [_before, quick_start] = String.split(readme, "## Quick start", parts: 2)
    [_prose, code | _rest] = String.split(quick_start, ["```elixir\n", "```\n"])
    ["client = " <> _client | program] = String.split(code, "\n")
    Enum.join(program, "\n")
  end
end
