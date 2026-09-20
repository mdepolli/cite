defmodule Cite.CandidateTest do
  use ExUnit.Case, async: true

  alias Cite.Candidate

  describe "from_segments/1" do
    test "assigns cumulative byte offsets for a space-joined document" do
      # Arrange
      segments = [
        %{text: "Hello there", meta: %{speaker: "A", start: 0, end: 1100}},
        %{text: "world", meta: %{speaker: "B", start: 1200, end: 1800}}
      ]

      # Act
      candidates = Candidate.from_segments(segments)
      source = Enum.map_join(candidates, " ", & &1.text)

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

    test "trims segment texts before offsets" do
      candidates =
        Candidate.from_segments([
          %{text: "  Hello there  "},
          %{text: "\tworld\n"}
        ])

      source = Enum.map_join(candidates, " ", & &1.text)
      [first, second] = candidates

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
      [first, second] = candidates = Candidate.from_segments(segments)
      source = Enum.map_join(candidates, " ", & &1.text)

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
      [candidate] = Candidate.from_segments([%{text: "hi", id: "turn-9"}])
      assert candidate.id == "turn-9"
    end

    test "defaults meta to an empty map" do
      [candidate] = Candidate.from_segments([%{text: "hi"}])
      assert candidate.meta == %{}
    end

    test "empty list yields no candidates" do
      assert Candidate.from_segments([]) == []
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

    test "raises when segment keys are strings" do
      assert_raise ArgumentError, ~r/missing required :text/, fn ->
        Candidate.from_segments([%{"text" => "hi"}])
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

    test "raises when :id is empty" do
      assert_raise ArgumentError, ~r/:id must be a non-empty binary/, fn ->
        Candidate.from_segments([%{text: "hi", id: ""}])
      end
    end

    test "raises listing every duplicated id, including auto-generated collisions" do
      assert_raise ArgumentError, ~r/ids must be unique, duplicated: \["C001", "x"\]/, fn ->
        Candidate.from_segments([
          %{text: "a", id: "C001"},
          %{text: "b"},
          %{text: "c", id: "x"},
          %{text: "d", id: "x"}
        ])
      end
    end

    test "raises when :meta is not a map" do
      assert_raise ArgumentError, ~r/:meta must be a map/, fn ->
        Candidate.from_segments([%{text: "hi", meta: "nope"}])
      end
    end
  end
end
