defmodule Cite.ClusterTest do
  use ExUnit.Case, async: true

  alias Cite.Candidate
  alias Cite.Cluster
  alias Cite.Question

  defp cand(id, text \\ "x") do
    %Candidate{id: id, text: text, byte_start: 0, byte_end: byte_size(text), meta: %{}}
  end

  defp q(key \\ "fits") do
    %{
      key =>
        Question.noul(
          question: "Q?",
          inspect: "`x`",
          true: "yes",
          false: "no"
        )
    }
  end

  describe "new/1" do
    test "builds a cluster struct with defaults for match and member_questions" do
      member = cand("U001", "hello")

      cluster =
        Cluster.new(
          id: "life_event:U001",
          class: "life_events",
          members: [member],
          state: %{"utterances" => %{"U001" => Cluster.member_state(member)}},
          questions: q()
        )

      assert %Cluster{} = cluster
      assert cluster.id == "life_event:U001"
      assert cluster.class == "life_events"
      assert cluster.members == [member]
      assert cluster.match == :all
      assert cluster.member_questions == %{}
      assert %Question{type: :noul} = cluster.questions["fits"]
    end

    test "honours explicit match and member_questions" do
      a = cand("U001")
      b = cand("U002")

      same =
        Question.noul(
          question: "Same household?",
          inspect: ["`a`", "`b`"],
          true: "yes",
          false: "no"
        )

      cluster =
        Cluster.new(%{
          id: "household_income",
          class: "resilience",
          members: [a, b],
          state: %{},
          questions: %{"same_household" => same},
          match: :any,
          member_questions: %{"U001" => ["same_household"]}
        })

      assert cluster.match == :any
      assert cluster.member_questions == %{"U001" => ["same_household"]}
    end

    test "raises when a required key is missing" do
      assert_raise ArgumentError, ~r/missing required keys: \[:id\]/, fn ->
        Cluster.new(
          class: "x",
          members: [cand("U001")],
          state: %{},
          questions: q()
        )
      end
    end

    test "raises when members is empty" do
      assert_raise ArgumentError, ~r/non-empty list/, fn ->
        Cluster.new(id: "x", class: "y", members: [], state: %{}, questions: q())
      end
    end

    test "raises when a member is not a Candidate" do
      assert_raise ArgumentError, ~r/Cite.Candidate/, fn ->
        Cluster.new(
          id: "x",
          class: "y",
          members: [%{id: "U001"}],
          state: %{},
          questions: q()
        )
      end
    end

    test "raises on duplicate member ids" do
      a = cand("U001")

      assert_raise ArgumentError, ~r/duplicated: \["U001"\]/, fn ->
        Cluster.new(
          id: "x",
          class: "y",
          members: [a, a],
          state: %{},
          questions: q()
        )
      end
    end

    test "allows empty questions for atomic-only emit" do
      empty = Map.drop(%{"fits" => q()["fits"]}, ["fits"])

      cluster =
        Cluster.new(
          id: "x",
          class: "y",
          members: [cand("U001")],
          state: %{},
          questions: empty
        )

      assert cluster.questions == %{}
    end

    test "raises on empty question keys" do
      assert_raise ArgumentError, ~r/non-empty binary => Cite.Question/, fn ->
        Cluster.new(
          id: "x",
          class: "y",
          members: [cand("U001")],
          state: %{},
          questions: %{"" => q()["fits"]}
        )
      end
    end

    test "raises ArgumentError when attrs is a struct" do
      assert_raise ArgumentError, ~r/map or keyword list/, fn ->
        Cluster.new(URI.parse("https://example.com"))
      end
    end

    test "raises when member_questions lists are empty" do
      assert_raise ArgumentError, ~r/non-empty \[question_key\]/, fn ->
        Cluster.new(
          id: "x",
          class: "y",
          members: [cand("U001")],
          state: %{},
          questions: q("fits"),
          member_questions: %{"U001" => []}
        )
      end
    end

    test "raises when a questions value is not a Question" do
      assert_raise ArgumentError, ~r/binary => Cite.Question/, fn ->
        Cluster.new(
          id: "x",
          class: "y",
          members: [cand("U001")],
          state: %{},
          questions: %{"fits" => %{type: :noul}}
        )
      end
    end

    test "raises when member_questions id is not a member" do
      assert_raise ArgumentError, ~r/not cluster members: \["U999"\]/, fn ->
        Cluster.new(
          id: "x",
          class: "y",
          members: [cand("U001")],
          state: %{},
          questions: q("fits"),
          member_questions: %{"U999" => ["fits"]}
        )
      end
    end

    test "raises when member_questions key is missing from questions" do
      assert_raise ArgumentError, ~r/not in questions: \["fits:health:U01"\]/, fn ->
        Cluster.new(
          id: "x",
          class: "y",
          members: [cand("U010")],
          state: %{},
          questions: q("fits:health:U010"),
          member_questions: %{"U010" => ["fits:health:U01"]}
        )
      end
    end

    test "raises on non-keyword list" do
      assert_raise ArgumentError, ~r/keyword list/, fn ->
        Cluster.new([1, 2])
      end
    end

    test "raises on bad match" do
      assert_raise ArgumentError, ~r/match must be/, fn ->
        Cluster.new(
          id: "x",
          class: "y",
          members: [cand("U001")],
          state: %{},
          questions: q(),
          match: :sometimes
        )
      end
    end

    test "raises on empty id" do
      assert_raise ArgumentError, ~r/non-empty binary/, fn ->
        Cluster.new(id: "", class: "y", members: [cand("U001")], state: %{}, questions: q())
      end
    end
  end

  describe "member_state/1" do
    test "packs id text and speaker from atom meta" do
      c = %Candidate{
        id: "U010",
        text: "hi",
        byte_start: 0,
        byte_end: 2,
        meta: %{speaker: "A"}
      }

      assert Cluster.member_state(c) == %{id: "U010", text: "hi", speaker: "A"}
    end

    test "raises on non-candidate" do
      assert_raise ArgumentError, ~r/Cite.Candidate/, fn ->
        Cluster.member_state(%{id: "U001"})
      end
    end
  end
end
