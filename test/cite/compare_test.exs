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
    members = Keyword.get(opts, :members, [cand("U0"), cand("U1", 2)])

    Cluster.new(
      id: Keyword.get(opts, :id, "c"),
      class: "k",
      members: members,
      state: Keyword.get(opts, :state, %{}),
      questions: Keyword.get(opts, :questions, %{"fits" => noul_q()}),
      member_questions: Keyword.get(opts, :member_questions, %{}),
      match: Keyword.get(opts, :match, :all)
    )
  end

  defp noul(value), do: %{"noul" => value}

  describe "request/2" do
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

  describe "decide/3 gate" do
    test "accepts when every Noul clears the high edge" do
      assert {:accept, [_, _]} = Compare.decide(cluster([]), %{"fits" => noul(0.9)}, @band)
    end

    test "reviews when a Noul lands inside the band" do
      assert {:review, _} = Compare.decide(cluster([]), %{"fits" => noul(0.5)}, @band)
    end

    test "rejects when any Noul is at or below the low edge" do
      assert {:reject, _} = Compare.decide(cluster([]), %{"fits" => noul(0.4)}, @band)
    end

    test ":all counts an unanswered Noul as 0.0" do
      cluster = cluster(questions: %{"fits" => noul_q(), "also" => noul_q()})
      assert {:reject, _} = Compare.decide(cluster, %{"fits" => noul(0.9)}, @band)
    end

    test ":any accepts on one clearing Noul and reviews on one above the low edge" do
      cluster = cluster(match: :any, questions: %{"a" => noul_q(), "b" => noul_q()})
      assert {:accept, _} = Compare.decide(cluster, %{"a" => noul(0.9), "b" => noul(0.1)}, @band)
      assert {:review, _} = Compare.decide(cluster, %{"a" => noul(0.5), "b" => noul(0.1)}, @band)
      assert {:reject, _} = Compare.decide(cluster, %{"a" => noul(0.4), "b" => noul(0.1)}, @band)
    end

    test "accepts a cluster with only Score and Choice questions" do
      cluster = cluster(questions: %{"severity" => score_q()})
      answers = %{"severity" => %{"score" => 1, "confidence" => 0.9}}
      assert {:accept, [_, _]} = Compare.decide(cluster, answers, @band)
    end
  end

  describe "decide/3 evidence" do
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
      assert {:accept, [%Candidate{id: "U0"}]} = Compare.decide(cluster, answers, @band)
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
               Compare.decide(cluster, answers, @band)
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
      assert {:reject, []} = Compare.decide(cluster, answers, @band)
    end
  end

  describe "resolve/2" do
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
      assert [{^accept, [_, _], _, false}, {^review, [_, _], _, true}] = resolved.accepted

      assert resolved.rejected == %{
               "x" => %{"members" => ["U0", "U1"], "answers" => %{"fits" => noul(0.1)}}
             }

      assert resolved.errors == [%Error{byte_start: 10, byte_end: 21, reason: :boom}]
      assert resolved.usages == [%{input_tokens: 1, output_tokens: 0}, nil, nil]
    end
  end
end
