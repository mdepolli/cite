defmodule Cite.ScanTest do
  use ExUnit.Case, async: true

  alias Cite.{Candidate, Error, Question, Scan}

  defp cand(id, text, start, meta \\ %{}) do
    %Candidate{
      id: id,
      text: text,
      byte_start: start,
      byte_end: start + byte_size(text),
      meta: meta
    }
  end

  defp atomic(name) do
    %{
      name: name,
      question: fn %Candidate{id: id} ->
        Question.noul(question: "#{name} for #{id}?", inspect: "`x`", true: "y", false: "n")
      end
    }
  end

  describe "candidates/2" do
    @source "aaaa bbbb"

    test "returns candidates with unique ids that slice the source to their text" do
      candidates = [cand("U0", "aaaa", 0), cand("U1", "bbbb", 5)]
      assert Scan.candidates(candidates, @source) == candidates
    end

    test "raises on duplicate ids" do
      assert_raise ArgumentError, ~r/candidate ids must be unique, duplicated: \["U0"\]/, fn ->
        Scan.candidates([cand("U0", "aaaa", 0), cand("U0", "bbbb", 5)], @source)
      end
    end

    test "raises when the source slice does not equal the candidate text" do
      assert_raise ArgumentError, ~r/"U1" text does not match source at \[5, 9\)/, fn ->
        Scan.candidates([cand("U1", "bbbc", 5)], @source)
      end
    end

    test "raises on inverted or out-of-range offsets, and on a non-candidate" do
      inverted = %Candidate{id: "U0", text: "aaaa", byte_start: 4, byte_end: 0}
      outside = %Candidate{id: "U0", text: "aaaa", byte_start: 6, byte_end: 10}

      for bad <- [inverted, outside] do
        assert_raise ArgumentError, ~r/"U0" has invalid offsets/, fn ->
          Scan.candidates([bad], @source)
        end
      end

      assert_raise ArgumentError, ~r/expected a Candidate/, fn ->
        Scan.candidates([%{id: "U0"}], @source)
      end
    end
  end

  describe "request/3" do
    test "asks every atomic of every candidate over the wired state" do
      # Arrange
      window = [cand("U0", "aaaa", 0, %{speaker: "A"}), cand("U1", "bbbb", 5)]
      atomics = [atomic("dependents"), atomic("income")]

      # Act
      request = Scan.request(window, atomics, %{meeting: "m1"})

      # Assert
      assert Enum.sort(Map.keys(request["questions"])) ==
               ["U0:dependents", "U0:income", "U1:dependents", "U1:income"]

      assert request["questions"]["U1:income"]["instructions"]["question"] == "income for U1?"

      assert request["state"] == %{
               "meeting" => "m1",
               "candidates" => %{
                 "U0" => %{"id" => "U0", "text" => "aaaa", "speaker" => "A"},
                 "U1" => %{"id" => "U1", "text" => "bbbb"}
               }
             }
    end
  end

  describe "resolve/2" do
    test "builds the index from answers, one row per candidate, missing answers as 0.0" do
      # Arrange
      window = [cand("U0", "aaaa", 0), cand("U1", "bbbb", 5)]
      answers = %{"U0:dependents" => %{"noul" => 0.9}, "U1:dependents" => %{"noul" => 0.2}}
      outcomes = [{window, {:ok, %{answers: answers, usage: nil}}}]

      # Act
      resolved = Scan.resolve(outcomes, [atomic("dependents"), atomic("income")])

      # Assert
      assert resolved.index == %{
               "U0" => %{"dependents" => 0.9, "income" => 0.0},
               "U1" => %{"dependents" => 0.2, "income" => 0.0}
             }

      assert resolved.errors == []
      assert resolved.usages == [nil]
    end

    test "raises when a verdict has no answers" do
      assert_raise ArgumentError, ~r/verdict must carry :answers/, fn ->
        Scan.resolve([{[cand("U0", "aaaa", 0)], {:ok, %{usage: nil}}}], [atomic("d")])
      end
    end

    test "records one error spanning a failed window and keeps its usage out" do
      # Arrange
      good = [cand("U0", "aaaa", 0)]
      bad = [cand("U2", "cccc", 10), cand("U1", "bbbb", 5)]

      outcomes = [
        {good,
         {:ok,
          %{answers: %{"U0:d" => %{"noul" => 1.0}}, usage: %{input_tokens: 3, output_tokens: 0}}}},
        {bad, {:error, :boom}}
      ]

      # Act
      resolved = Scan.resolve(outcomes, [atomic("d")])

      # Assert
      assert Map.keys(resolved.index) == ["U0"]
      assert resolved.errors == [%Error{byte_start: 5, byte_end: 14, reason: :boom}]
      assert resolved.usages == [%{input_tokens: 3, output_tokens: 0}]
    end
  end

  describe "drop_below/2" do
    test "drops scores at or below the threshold but keeps every row" do
      index = %{"U0" => %{"a" => 0.9, "b" => 0.5}, "U1" => %{"a" => 0.1}}
      assert Scan.drop_below(index, 0.5) == %{"U0" => %{"a" => 0.9}, "U1" => %{}}
    end
  end
end
