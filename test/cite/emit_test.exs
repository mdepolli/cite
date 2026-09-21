defmodule Cite.EmitTest do
  use ExUnit.Case, async: true

  alias Cite.{Candidate, Cluster, Emit, Question, Span}

  @source "Four kids at home. I make 180k."

  defp members do
    [
      %Candidate{id: "U0", text: "Four kids at home.", byte_start: 0, byte_end: 18},
      %Candidate{id: "U1", text: "I make 180k.", byte_start: 19, byte_end: 31}
    ]
  end

  defp cluster(questions) do
    Cluster.new(
      id: "household",
      class: "resilience",
      members: members(),
      state: %{},
      questions: questions
    )
  end

  defp questions do
    %{
      "fits" => Question.noul(question: "Q?", inspect: "`x`", true: "y", false: "n"),
      "severity" => Question.score(question: "S?", inspect: "`x`", criteria: ["a", "b", "c"]),
      "temporal" =>
        Question.choice(question: "T?", inspect: "`x`", criteria: %{"t" => "x", "p" => "y"})
    }
  end

  test "emits one byte-exact span per grounded member with class and attributes" do
    # Arrange
    cluster = cluster(questions())

    answers = %{
      "fits" => %{"noul" => 0.9},
      "severity" => %{"score" => 1.2, "confidence" => 0.9},
      "temporal" => %{"choice" => "p", "confidence" => 0.8}
    }

    # Act
    spans =
      Emit.spans(
        @source,
        [%{cluster: cluster, members: members(), answers: answers, review?: false}],
        0.5
      )

    # Assert
    assert [
             %Span{text: "Four kids at home.", byte_start: 0, byte_end: 18, candidate_id: "U0"},
             %Span{text: "I make 180k.", byte_start: 19, byte_end: 31, candidate_id: "U1"}
           ] = spans

    assert Enum.all?(spans, &(&1.class == "resilience"))

    assert hd(spans).attributes == %{
             "cluster_id" => "household",
             "compare" => answers,
             "review" => false,
             "severity" => 1,
             "temporal" => "p"
           }
  end

  test "labels score and choice uncertain below the confidence floor, and Nouls not at all" do
    # Arrange
    cluster = cluster(questions())

    answers = %{
      "fits" => %{"noul" => 0.9},
      "severity" => %{"score" => 1.0, "confidence" => 0.3},
      "temporal" => %{"choice" => "p", "confidence" => 0.2}
    }

    # Act
    [span | _] =
      Emit.spans(
        @source,
        [%{cluster: cluster, members: members(), answers: answers, review?: true}],
        0.5
      )

    # Assert
    assert span.attributes["severity"] == "uncertain"
    assert span.attributes["temporal"] == "uncertain"
    assert span.attributes["review"] == true
    refute Map.has_key?(span.attributes, "fits")
  end

  test "grounds only the members it is handed" do
    [only] =
      Emit.spans(
        @source,
        [
          %{cluster: cluster(%{}), members: [hd(members())], answers: %{}, review?: false}
        ],
        0.5
      )

    assert only.candidate_id == "U0"
  end
end
