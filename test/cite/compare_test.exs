defmodule Cite.CompareTest do
  use ExUnit.Case, async: true

  alias Cite.{Candidate, Cluster, Compare, Error, Question}

  @band {0.4, 0.6}

  defp cand(id, start \\ 0) do
    %Candidate{id: id, text: "t", byte_start: start, byte_end: start + 1, meta: %{speaker: "A"}}
  end

  defp noul_q, do: Question.noul(question: "Q?", inspect: "`x`", true: "y", false: "n")
  defp score_q, do: Question.score(question: "S?", inspect: "`x`", criteria: ["a", "b"])

  defp cluster(opts) do
    id = Keyword.get(opts, :id, "c")
    members = Keyword.get(opts, :members, [cand("U0"), cand("U1", 2)])
    state = Keyword.get(opts, :state, %{})
    questions = Keyword.get(opts, :questions, %{"fits" => noul_q()})
    member_questions = Keyword.get(opts, :member_questions, %{})
    match = Keyword.get(opts, :match, :all)

    Cluster.new(
      id: id,
      class: "k",
      members: members,
      state: state,
      questions: questions,
      member_questions: member_questions,
      match: match
    )
  end

  defp noul(value), do: %{"noul" => value}

  # One judged cluster through resolve/2, read back as its decision.
  defp decide(cluster, answers) do
    resolved = Compare.resolve([{cluster, {:ok, %{answers: answers, usage: nil}}}], @band)

    case resolved do
      %{accepted: [%{members: members, review?: false}]} -> {:accept, members}
      %{accepted: [%{members: members, review?: true}]} -> {:review, members}
      %{accepted: [], rejected: %{}} -> :reject
    end
  end

  describe "clusters/2" do
    test "returns the clusters when every member is a known candidate" do
      clusters = [cluster(id: "a"), cluster(id: "b")]
      assert Compare.clusters(clusters, [cand("U0"), cand("U1", 2)]) == clusters
    end

    test "raises when a member is not among the candidates" do
      assert_raise ArgumentError, ~r/cluster "c" member "U9" is not in candidates/, fn ->
        Compare.clusters([cluster(members: [cand("U9")])], [cand("U0")])
      end
    end

    test "raises on a hand-built cluster with no members" do
      empty = %Cluster{id: "e", class: "k", members: [], state: %{}, questions: %{}}

      assert_raise ArgumentError, ~r/cluster "e" has no members/, fn ->
        Compare.clusters([empty], [cand("U0")])
      end
    end

    test "raises on duplicate cluster ids" do
      assert_raise ArgumentError, ~r/duplicate cluster ids: \["c", "c"\]/, fn ->
        Compare.clusters([cluster([]), cluster([])], [cand("U0"), cand("U1", 2)])
      end
    end

    test "raises when compose returns something other than a cluster list" do
      assert_raise ArgumentError, ~r/must return a list of clusters/, fn ->
        Compare.clusters(:nope, [])
      end

      assert_raise ArgumentError, ~r/must return Cluster structs/, fn ->
        Compare.clusters([%{id: "x"}], [])
      end
    end
  end

  describe "request/2" do
    test "is nil when the cluster has no questions" do
      assert Compare.request(cluster(questions: %{}), %{}) == nil
    end

    test "overlays the cluster state on the extra state and encodes the questions" do
      # Arrange
      cluster = cluster(state: %{"household" => cand("U0"), shared: "mine"})

      # Act
      request = Compare.request(cluster, %{shared: "theirs", meeting: "m"})

      # Assert
      assert request["state"] == %{
               "meeting" => "m",
               "shared" => "mine",
               "household" => %{"id" => "U0", "text" => "t", "speaker" => "A"}
             }

      assert %{"fits" => %{"type" => "noul"}} = request["questions"]
    end
  end

  describe "resolve/2 gate" do
    test "accepts when every Noul clears the high edge" do
      assert {:accept, [_, _]} = decide(cluster([]), %{"fits" => noul(0.9)})
    end

    test "reviews when a Noul lands inside the band" do
      assert {:review, _} = decide(cluster([]), %{"fits" => noul(0.5)})
    end

    test "rejects when any Noul is at or below the low edge" do
      assert :reject == decide(cluster([]), %{"fits" => noul(0.4)})
    end

    test ":all counts a malformed Noul answer as 0.0" do
      cluster = cluster(questions: %{"fits" => noul_q(), "also" => noul_q()})
      assert :reject == decide(cluster, %{"fits" => noul(0.9), "also" => %{"noul" => "high"}})
    end

    test ":any accepts on one clearing Noul and reviews on one above the low edge" do
      cluster = cluster(match: :any, questions: %{"a" => noul_q(), "b" => noul_q()})
      assert {:accept, _} = decide(cluster, %{"a" => noul(0.9), "b" => noul(0.1)})
      assert {:review, _} = decide(cluster, %{"a" => noul(0.5), "b" => noul(0.1)})
      assert :reject == decide(cluster, %{"a" => noul(0.4), "b" => noul(0.1)})
    end

    test "accepts a cluster with only Score and Choice questions" do
      cluster = cluster(questions: %{"severity" => score_q()})
      answers = %{"severity" => %{"score" => 1, "confidence" => 0.9}}
      assert {:accept, [_, _]} = decide(cluster, answers)
    end
  end

  describe "resolve/2 evidence" do
    test "grounds only named members whose own Noul clears the low edge" do
      # Arrange
      cluster =
        cluster(
          match: :any,
          questions: %{"fits" => noul_q(), "fits:U0" => noul_q(), "fits:U1" => noul_q()},
          member_questions: %{"U0" => ["fits:U0"], "U1" => ["fits:U1"]}
        )

      answers = %{"fits" => noul(0.9), "fits:U0" => noul(0.9), "fits:U1" => noul(0.1)}

      # Act + Assert
      assert {:accept, [%Candidate{id: "U0"}]} = decide(cluster, answers)
    end

    test "members not named in member_questions are always evidence" do
      # Arrange
      cluster =
        cluster(
          questions: %{"fits" => noul_q(), "fits:U0" => noul_q()},
          member_questions: %{"U0" => ["fits:U0"]}
        )

      answers = %{"fits" => noul(0.9), "fits:U0" => noul(0.9)}

      # Act + Assert
      assert {:accept, [%Candidate{id: "U0"}, %Candidate{id: "U1"}]} =
               decide(cluster, answers)
    end

    test "rejects a cluster that clears the gate but grounds no member" do
      # Arrange
      cluster =
        cluster(
          match: :any,
          questions: %{"fits" => noul_q(), "fits:U0" => noul_q(), "fits:U1" => noul_q()},
          member_questions: %{"U0" => ["fits:U0"], "U1" => ["fits:U1"]}
        )

      answers = %{"fits" => noul(0.9), "fits:U0" => noul(0.1), "fits:U1" => noul(0.1)}

      # Act + Assert
      assert :reject == decide(cluster, answers)
    end
  end

  describe "resolve/2" do
    test "accepts an unasked cluster with every member and no usage" do
      # Arrange
      cluster = cluster(id: "free", questions: %{})

      # Act
      resolved = Compare.resolve([{cluster, :unasked}], @band)

      # Assert
      assert [%{cluster: ^cluster, members: [_, _], answers: %{}, review?: false}] =
               resolved.accepted

      assert resolved.usages == []
    end

    test "buckets decisions, keeps rejected answers, and spans errors over members" do
      # Arrange
      accept = cluster(id: "a")
      review = cluster(id: "r")
      reject = cluster(id: "x")
      failed = cluster(id: "f", members: [cand("U5", 20), cand("U4", 10)])

      outcomes = [
        {accept,
         {:ok, %{answers: %{"fits" => noul(0.9)}, usage: %{input_tokens: 1, output_tokens: 0}}}},
        {review, {:ok, %{answers: %{"fits" => noul(0.5)}, usage: nil}}},
        {reject, {:ok, %{answers: %{"fits" => noul(0.1)}, usage: nil}}},
        {failed, {:error, :boom}}
      ]

      # Act
      resolved = Compare.resolve(outcomes, @band)

      # Assert
      assert [
               %{cluster: ^accept, members: [_, _], review?: false},
               %{cluster: ^review, members: [_, _], review?: true}
             ] = resolved.accepted

      assert resolved.rejected == %{
               "x" => %{"members" => ["U0", "U1"], "answers" => %{"fits" => noul(0.1)}}
             }

      assert resolved.errors == [
               %Error{byte_start: 10, byte_end: 21, candidate_ids: ["U5", "U4"], reason: :boom}
             ]

      assert resolved.usages == [%{input_tokens: 1, output_tokens: 0}, nil, nil]
    end
  end
end
