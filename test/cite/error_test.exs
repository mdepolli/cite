defmodule Cite.ErrorTest do
  use ExUnit.Case, async: true

  alias Cite.Error

  describe "from_range/3" do
    test "builds an error for a byte range" do
      assert %Error{byte_start: 0, byte_end: 10, reason: :timeout} =
               Error.from_range(0, 10, :timeout)
    end

    test "raises on inverted range" do
      assert_raise ArgumentError, fn ->
        Error.from_range(10, 0, :timeout)
      end
    end
  end

  describe "from_candidates/2" do
    test "spans the candidates' bytes and records their ids in the order given" do
      candidates = [
        %Cite.Candidate{id: "U2", text: "cc", byte_start: 6, byte_end: 8},
        %Cite.Candidate{id: "U1", text: "bb", byte_start: 3, byte_end: 5}
      ]

      assert Error.from_candidates(candidates, :boom) ==
               %Error{byte_start: 3, byte_end: 8, candidate_ids: ["U2", "U1"], reason: :boom}
    end
  end

  describe "Jason.Encoder" do
    test "encodes atom reasons as strings" do
      error = Error.from_range(0, 10, :timeout)

      assert Jason.decode!(Jason.encode!(error)) == %{
               "byte_start" => 0,
               "byte_end" => 10,
               "candidate_ids" => [],
               "reason" => "timeout"
             }
    end

    test "passes through binaries maps and lists" do
      assert Jason.decode!(Jason.encode!(Error.from_range(0, 1, "x")))["reason"] == "x"

      assert Jason.decode!(Jason.encode!(Error.from_range(0, 1, %{"tag" => "a"})))["reason"] ==
               %{"tag" => "a"}

      assert Jason.decode!(Jason.encode!(Error.from_range(0, 1, ["a", 1])))["reason"] == ["a", 1]
    end

    test "inspects tuples and exception structs so dumps never crash" do
      tuple = Error.from_range(0, 10, {:bad_request, "max_tokens_exceeded"})

      assert Jason.decode!(Jason.encode!(tuple))["reason"] ==
               ~s({:bad_request, "max_tokens_exceeded"})

      exception = Error.from_range(0, 10, %RuntimeError{message: "boom"})

      assert Jason.decode!(Jason.encode!(exception))["reason"] ==
               ~s(%RuntimeError{message: "boom"})
    end

    test "inspects tuples nested inside lists and maps" do
      nested = Error.from_range(0, 1, %{"causes" => [{:a, 1}, "ok"], "meta" => %{k: {:b, 2}}})

      assert Jason.decode!(Jason.encode!(nested))["reason"] ==
               %{"causes" => ["{:a, 1}", "ok"], "meta" => %{"k" => "{:b, 2}"}}
    end
  end
end
