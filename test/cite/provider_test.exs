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

    test "raises on a provider that is not a module implementing Cite.Provider" do
      for provider <- ["Cite.Provider.TypeSafe", :not_a_module, Enum] do
        assert_raise ArgumentError,
                     ~r/provider must be a module implementing Cite.Provider/,
                     fn ->
                       Cite.client(provider, api_key: "k")
                     end
      end
    end

    test "raises on provider options that are not a keyword list" do
      for {opts, message} <- [
            {%{score: 0.9}, "provider options must be a keyword list, got: %{score: 0.9}"},
            {[1, 2], "provider options must be a keyword list, got: [1, 2]"}
          ] do
        assert_raise ArgumentError, message, fn -> Cite.client(Echo, opts) end
      end
    end
  end
end
