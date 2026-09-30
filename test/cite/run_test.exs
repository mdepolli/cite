defmodule Cite.RunTest do
  use ExUnit.Case, async: true

  alias Cite.{Run, TestRun, TestTerms}
  alias Cite.TestPolicies.Riddles

  defp client, do: fn _request -> :unused end

  describe "new/4" do
    test "defaults the options Cite.TestRun hard-codes for the pure steps" do
      keys = [:threshold, :review_band, :window, :concurrency]
      run = Run.new(client(), Cite.source(["a"]), Riddles, [])

      assert Map.take(run, keys) == Map.take(TestRun.new(TestTerms.riddles()), keys)
    end

    test "raises on a client, source, policy, or options of the wrong kind" do
      for {client, source, policy, opts, message} <- [
            {:not_a_function, Cite.source(["a"]), Riddles, [],
             "client must be a 1-arity function, got: :not_a_function"},
            {client(), ["a"], Riddles, [],
             ~s(source must be a Cite.Source, built by Cite.source/2, got: ["a"])},
            {client(), Cite.source(["a"]), "Riddles", [],
             ~s("Riddles" is not a Cite policy; it must `use Cite.Policy`)},
            {client(), Cite.source(["a"]), Riddles, %{window: 4},
             "options must be a keyword list, got: %{window: 4}"}
          ] do
        assert_raise ArgumentError, message, fn -> Run.new(client, source, policy, opts) end
      end
    end

    test "raises on unknown or invalid options, naming the option" do
      for {opts, message} <- [
            {[review_band: {0.6, 0.4}],
             "invalid value for :review_band option: expected {low, high} with 0 <= low < high <= 1, got: {0.6, 0.4}"},
            {[review_band: {0.4, 1.5}],
             "invalid value for :review_band option: expected {low, high} with 0 <= low < high <= 1, got: {0.4, 1.5}"},
            {[window: 0], "invalid value for :window option: expected positive integer, got: 0"},
            {[threshold: "high"],
             ~s(invalid value for :threshold option: expected a number from 0 to 1, got: "high")},
            {[threshold: 5],
             "invalid value for :threshold option: expected a number from 0 to 1, got: 5"},
            {[colour: :red],
             "unknown options [:colour], valid options are: [:threshold, :review_band, :window, :concurrency]"}
          ] do
        assert_raise ArgumentError, message, fn ->
          Run.new(client(), Cite.source(["a"]), Riddles, opts)
        end
      end
    end
  end
end
