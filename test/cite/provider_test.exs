defmodule Cite.ProviderTest do
  use ExUnit.Case, async: true

  defmodule Echo do
    @behaviour Cite.Provider

    @impl Cite.Provider
    def new(opts), do: %{score: Keyword.get(opts, :score, 0.5)}

    @impl Cite.Provider
    def judge(%{score: score}, %{"questions" => questions}) do
      {:ok,
       %{answers: Map.new(questions, fn {key, _} -> {key, %{"noul" => score}} end), usage: nil}}
    end
  end

  @request %{"state" => %{}, "questions" => %{"U0:d" => %{"type" => "noul"}}}

  test "judge/2 closes a custom provider's client into the judge function" do
    judge = Cite.judge(Echo, score: 0.9)

    assert is_function(judge, 1)
    assert judge.(@request) == {:ok, %{answers: %{"U0:d" => %{"noul" => 0.9}}, usage: nil}}
  end

  test "judge/1 takes a provider module with no options" do
    assert {:ok, %{answers: %{"U0:d" => %{"noul" => 0.5}}}} = Cite.judge(Echo).(@request)
  end

  test "a custom provider runs the whole pipeline" do
    candidates = Cite.Candidate.from_segments([%{text: "four kids at home"}])
    source = Enum.map_join(candidates, " ", & &1.text)

    spec = %{
      atomics: [
        %{
          name: "dependents",
          question: fn _ ->
            Cite.Question.noul(question: "Kids?", inspect: "`x`", true: "y", false: "n")
          end
        }
      ],
      compose: fn index, [candidate] ->
        assert index == %{"C000" => %{"dependents" => 0.9}}

        [
          Cite.Cluster.new(
            id: "c",
            class: "k",
            members: [candidate],
            state: %{"line" => candidate},
            questions: %{}
          )
        ]
      end
    }

    result = Cite.select(Cite.judge(Echo, score: 0.9), source, candidates, spec)
    assert [%Cite.Span{candidate_id: "C000", text: "four kids at home"}] = result.spans
  end
end
