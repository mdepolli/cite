defmodule Cite.SpanTest do
  use ExUnit.Case, async: true

  alias Cite.Candidate
  alias Cite.Span

  describe "from_candidates/2" do
    test "copies candidate byte ranges and keeps candidate_id" do
      # Arrange
      source = "Hello there world"

      candidates = [
        %Candidate{id: "U000", text: "Hello there", byte_start: 0, byte_end: 11},
        %Candidate{id: "U001", text: "world", byte_start: 12, byte_end: 17}
      ]

      # Act
      spans = Span.from_candidates(source, candidates)

      # Assert
      assert [
               %Span{text: "Hello there", byte_start: 0, byte_end: 11, candidate_id: "U000"},
               %Span{text: "world", byte_start: 12, byte_end: 17, candidate_id: "U001"}
             ] = spans
    end

    test "raises when the source slice does not equal candidate text" do
      source = "Hello

there"
      candidate = %Candidate{id: "U000", text: "there", byte_start: 6, byte_end: 11}

      assert_raise ArgumentError, ~r/does not match source slice/, fn ->
        Span.from_candidates(source, [candidate])
      end
    end

    test "raises when offsets are inverted" do
      source = "Hello there"
      candidate = %Candidate{id: "U000", text: "there", byte_start: 11, byte_end: 6}

      assert_raise ArgumentError, ~r/invalid candidate offsets/, fn ->
        Span.from_candidates(source, [candidate])
      end
    end

    test "raises when offsets fall outside the source" do
      source = "Hi"
      candidate = %Candidate{id: "U000", text: "Hi!", byte_start: 0, byte_end: 3}

      assert_raise ArgumentError, ~r/invalid candidate offsets/, fn ->
        Span.from_candidates(source, [candidate])
      end
    end

    test "raises when given a non-list" do
      assert_raise ArgumentError, ~r/expected a list of candidates/, fn ->
        Span.from_candidates("Hi", %Candidate{id: "U000", text: "Hi", byte_start: 0, byte_end: 2})
      end
    end

    test "raises when an element is not a Candidate" do
      assert_raise ArgumentError, ~r/expected %Cite.Candidate{}/, fn ->
        Span.from_candidates("Hi", [%{id: "U000", text: "Hi", byte_start: 0, byte_end: 2}])
      end
    end
  end
end
