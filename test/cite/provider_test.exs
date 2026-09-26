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

  describe "Cite.client/2" do
    test "closes a custom provider's handle into the client function" do
      client = Cite.client(Echo, score: 0.9)

      assert client.(@request) == {:ok, %{answers: %{"U0:d" => %{"noul" => 0.9}}, usage: nil}}
    end

    test "takes a provider module with no options" do
      assert Cite.client(Echo).(@request) ==
               {:ok, %{answers: %{"U0:d" => %{"noul" => 0.5}}, usage: nil}}
    end
  end

  describe "a custom provider" do
    test "runs both rounds of Cite.judge/4" do
      # Arrange
      source = Cite.source(["Why is a raven like a writing-desk?"])

      # Act
      report = Cite.judge(Cite.client(Echo, score: 0.9), source, Cite.TestPolicies.Riddles)

      # Assert
      assert Enum.map(report.findings, &{&1.concern, &1.verdict}) == [riddle: :holds]
    end
  end
end
