defmodule Cite.ErrorTest do
  use ExUnit.Case, async: true

  alias Cite.Error

  describe "Jason.Encoder" do
    test "encodes the concern, passage ids, and an atom reason as strings" do
      error = %Error{concern: :household_income, passage_ids: ["U3", "U9"], reason: :timeout}

      assert Jason.decode!(Jason.encode!(error)) == %{
               "concern" => "household_income",
               "passage_ids" => ["U3", "U9"],
               "reason" => "timeout"
             }
    end

    test "encodes a screening error's missing concern as null" do
      error = %Error{concern: nil, passage_ids: ["P0"], reason: :timeout}

      assert Jason.decode!(Jason.encode!(error)) == %{
               "concern" => nil,
               "passage_ids" => ["P0"],
               "reason" => "timeout"
             }
    end

    test "passes through binaries, maps, and lists" do
      for {reason, encoded} <- [
            {"x", "x"},
            {%{"tag" => "a"}, %{"tag" => "a"}},
            {["a", 1], ["a", 1]}
          ] do
        error = %Error{concern: nil, passage_ids: [], reason: reason}
        assert Jason.decode!(Jason.encode!(error))["reason"] == encoded
      end
    end

    test "inspects tuples and exception structs so dumps never crash" do
      tuple = %Error{concern: nil, passage_ids: [], reason: {:bad_request, "max_tokens_exceeded"}}
      exception = %Error{concern: nil, passage_ids: [], reason: %RuntimeError{message: "boom"}}

      assert Jason.decode!(Jason.encode!(tuple))["reason"] ==
               ~s({:bad_request, "max_tokens_exceeded"})

      assert Jason.decode!(Jason.encode!(exception))["reason"] ==
               ~s(%RuntimeError{message: "boom"})
    end

    test "inspects tuples nested inside lists and maps" do
      error = %Error{
        concern: nil,
        passage_ids: [],
        reason: %{"causes" => [{:a, 1}, "ok"], "meta" => %{k: {:b, 2}}}
      }

      assert Jason.decode!(Jason.encode!(error))["reason"] ==
               %{"causes" => ["{:a, 1}", "ok"], "meta" => %{"k" => "{:b, 2}"}}
    end
  end
end
