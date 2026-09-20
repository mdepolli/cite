defmodule Cite.CandidateTest do
  use ExUnit.Case, async: true

  alias Cite.Candidate

  describe "from_segments/1" do
    test "joins segment texts with a space and assigns cumulative byte offsets" do
      # Arrange
      segments = [
        %{text: "Hello there", meta: %{speaker: "A", start: 0, end: 1100}},
        %{text: "world", meta: %{speaker: "B", start: 1200, end: 1800}}
      ]

      # Act
      {source, candidates} = Candidate.from_segments(segments)

      # Assert
      assert source == "Hello there world"

      assert [
               %Candidate{
                 id: "C000",
                 text: "Hello there",
                 byte_start: 0,
                 byte_end: 11,
                 meta: %{speaker: "A", start: 0, end: 1100}
               },
               %Candidate{
                 id: "C001",
                 text: "world",
                 byte_start: 12,
                 byte_end: 17,
                 meta: %{speaker: "B", start: 1200, end: 1800}
               }
             ] = candidates

      for %Candidate{} = candidate <- candidates do
        assert binary_part(
                 source,
                 candidate.byte_start,
                 candidate.byte_end - candidate.byte_start
               ) == candidate.text
      end
    end

    test "trims segment texts before join and offsets" do
      {source, [first, second]} =
        Candidate.from_segments([
          %{text: "  Hello there  "},
          %{text: "\tworld\n"}
        ])

      assert source == "Hello there world"
      assert first.text == "Hello there"
      assert second.text == "world"
      assert first.byte_start == 0
      assert first.byte_end == 11
      assert second.byte_start == 12
      assert second.byte_end == 17
    end

    test "offsets are bytes, not graphemes" do
      # Arrange — "£" is 2 bytes; "—" is 3
      segments = [
        %{text: "£100", meta: %{speaker: "A"}},
        %{text: "— okay", meta: %{speaker: "B"}}
      ]

      # Act
      {source, [first, second]} = Candidate.from_segments(segments)

      # Assert
      assert source == "£100 — okay"
      assert first.byte_start == 0
      assert first.byte_end == byte_size("£100")
      assert second.byte_start == first.byte_end + 1
      assert second.byte_end == byte_size(source)
      assert binary_part(source, first.byte_start, first.byte_end - first.byte_start) == "£100"

      assert binary_part(source, second.byte_start, second.byte_end - second.byte_start) ==
               "— okay"
    end

    test "honours an explicit segment id" do
      {_, [candidate]} = Candidate.from_segments([%{text: "hi", id: "turn-9"}])
      assert candidate.id == "turn-9"
    end

    test "defaults meta to an empty map" do
      {_, [candidate]} = Candidate.from_segments([%{text: "hi"}])
      assert candidate.meta == %{}
    end

    test "empty list yields empty source and no candidates" do
      assert Candidate.from_segments([]) == {"", []}
    end

    test "raises when given a non-list" do
      assert_raise ArgumentError, ~r/expected a list of segments/, fn ->
        Candidate.from_segments(%{text: "x"})
      end
    end

    test "raises when a segment is not a map" do
      assert_raise ArgumentError, ~r/segment must be a map/, fn ->
        Candidate.from_segments(["hi"])
      end
    end

    test "raises when :text is missing" do
      assert_raise ArgumentError, ~r/missing required :text/, fn ->
        Candidate.from_segments([%{id: "x"}])
      end
    end

    test "raises when :text is not a binary" do
      assert_raise ArgumentError, ~r/:text must be a binary/, fn ->
        Candidate.from_segments([%{text: 123}])
      end
    end

    test "raises when :text is blank after trim" do
      assert_raise ArgumentError, ~r/blank after trim/, fn ->
        Candidate.from_segments([%{text: "   "}])
      end
    end

    test "raises when :id is not a binary" do
      assert_raise ArgumentError, ~r/:id must be a binary/, fn ->
        Candidate.from_segments([%{text: "hi", id: :bad}])
      end
    end

    test "raises when :meta is not a map" do
      assert_raise ArgumentError, ~r/:meta must be a map/, fn ->
        Candidate.from_segments([%{text: "hi", meta: "nope"}])
      end
    end
  end
end
