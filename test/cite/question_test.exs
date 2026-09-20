defmodule Cite.QuestionTest do
  use ExUnit.Case, async: true

  alias Cite.Question

  describe "noul/1" do
    test "builds a noul question struct" do
      # Act
      question =
        Question.noul(
          question: "Is this true?",
          inspect: "`utterances.U001.text`",
          true: "yes case",
          false: "no case"
        )

      # Assert
      assert %Question{
               type: :noul,
               question: "Is this true?",
               inspect: "`utterances.U001.text`",
               criteria: %{
                 true: %{what: "yes case"},
                 false: %{what: "no case"}
               }
             } = question
    end

    test "passes through structured criteria maps" do
      true_c = %{what: "hit", examples: ["a"]}
      false_c = %{what: "miss", not_for: "noise"}

      question =
        Question.noul(
          question: "Q?",
          inspect: ["`a.text`", "`b.text`"],
          true: true_c,
          false: false_c
        )

      assert question.inspect == ["`a.text`", "`b.text`"]
      assert question.criteria[true] == true_c
      assert question.criteria[false] == false_c
    end

    test "raises when a required key is missing" do
      assert_raise ArgumentError, ~r/missing required key: false/, fn ->
        Question.noul(
          question: "Q?",
          inspect: "`x`",
          true: "t"
        )
      end
    end

    test "raises on unknown keys" do
      assert_raise ArgumentError, ~r/unknown keys \[:ask\]/, fn ->
        Question.noul(
          question: "Q?",
          inspect: "`x`",
          true: "t",
          false: "f",
          ask: "nope"
        )
      end
    end

    test "raises when question is not a binary" do
      assert_raise ArgumentError, ~r/question must be a non-empty binary/, fn ->
        Question.noul(
          question: :nope,
          inspect: "`x`",
          true: "t",
          false: "f"
        )
      end
    end

    test "raises when inspect is neither binary nor list of binaries" do
      assert_raise ArgumentError, ~r/inspect must be/, fn ->
        Question.noul(
          question: "Q?",
          inspect: %{path: "x"},
          true: "t",
          false: "f"
        )
      end
    end

    test "raises when inspect list contains a non-binary" do
      assert_raise ArgumentError, ~r/inspect list/, fn ->
        Question.noul(
          question: "Q?",
          inspect: ["`ok`", 1],
          true: "t",
          false: "f"
        )
      end
    end

    test "raises when criteria lacks what" do
      assert_raise ArgumentError, ~r/what must be a non-empty binary/, fn ->
        Question.noul(
          question: "Q?",
          inspect: "`x`",
          true: %{not_for: "x"},
          false: "f"
        )
      end
    end

    test "raises when given a non-keyword" do
      assert_raise ArgumentError, ~r/keyword list/, fn ->
        Question.noul(%{question: "Q?"})
      end
    end

    test "raises on empty inspect binary" do
      assert_raise ArgumentError, ~r/inspect must be a non-empty binary/, fn ->
        Question.noul(
          question: "Q?",
          inspect: "",
          true: "t",
          false: "f"
        )
      end
    end

    test "raises on empty inspect list" do
      empty = Enum.filter(["x"], fn _ -> false end)

      assert_raise ArgumentError, ~r/inspect list must be non-empty/, fn ->
        Question.noul(
          question: "Q?",
          inspect: empty,
          true: "t",
          false: "f"
        )
      end
    end

    test "raises on unknown criteria keys" do
      assert_raise ArgumentError, ~r/unknown keys: \[:exmaples\]/, fn ->
        Question.noul(
          question: "Q?",
          inspect: "`x`",
          true: %{what: "ok", exmaples: []},
          false: "f"
        )
      end
    end

    test "raises when criteria what is not a binary" do
      assert_raise ArgumentError, ~r/what must be a non-empty binary/, fn ->
        Question.noul(
          question: "Q?",
          inspect: "`x`",
          true: %{what: 1},
          false: "f"
        )
      end
    end
  end

  describe "score/1" do
    test "builds a score question struct" do
      question =
        Question.score(
          question: "How bad?",
          inspect: "`s.text`",
          criteria: ["low", "mid", "high"]
        )

      assert %Question{
               type: :score,
               question: "How bad?",
               inspect: "`s.text`",
               criteria: ["low", "mid", "high"]
             } = question
    end

    test "raises when criteria length is outside 2..10" do
      assert_raise ArgumentError, ~r/2\.\.10 labels, got 1/, fn ->
        Question.score(question: "Q?", inspect: "`x`", criteria: ["only"])
      end

      eleven = for i <- 1..11, do: "L#{i}"

      assert_raise ArgumentError, ~r/2\.\.10 labels, got 11/, fn ->
        Question.score(question: "Q?", inspect: "`x`", criteria: eleven)
      end
    end

    test "raises when criteria is not a list" do
      assert_raise ArgumentError, ~r/list of 2\.\.10 binaries/, fn ->
        Question.score(question: "Q?", inspect: "`x`", criteria: %{"a" => "b"})
      end
    end

    test "raises on blank or duplicate score labels" do
      assert_raise ArgumentError, ~r/non-empty binaries/, fn ->
        Question.score(question: "Q?", inspect: "`x`", criteria: ["", "low"])
      end

      assert_raise ArgumentError, ~r/duplicated: \["low"\]/, fn ->
        Question.score(question: "Q?", inspect: "`x`", criteria: ["low", "low"])
      end
    end

    test "raises when criteria is a struct" do
      assert_raise ArgumentError, ~r/map with :what/, fn ->
        Question.noul(
          question: "Q?",
          inspect: "`x`",
          true: URI.parse("https://example.com"),
          false: "f"
        )
      end
    end
  end

  describe "choice/1" do
    test "builds a choice question struct" do
      question =
        Question.choice(
          question: "Temp or lasting?",
          inspect: ["`a.text`"],
          criteria: %{
            "transient" => "short",
            "persistent" => "long"
          }
        )

      assert question.type == :choice
      assert question.criteria["transient"] == "short"
      assert question.inspect == ["`a.text`"]
    end

    test "raises on empty criteria map" do
      empty = Map.drop(%{"a" => "b"}, ["a"])

      assert_raise ArgumentError, ~r/non-empty map/, fn ->
        Question.choice(question: "Q?", inspect: "`x`", criteria: empty)
      end
    end

    test "raises when criteria values are not binaries" do
      assert_raise ArgumentError, ~r/non-empty binary => non-empty binary/, fn ->
        Question.choice(question: "Q?", inspect: "`x`", criteria: %{"a" => 1})
      end
    end

    test "raises on blank choice option ids or labels" do
      assert_raise ArgumentError, ~r/non-empty binary => non-empty binary/, fn ->
        Question.choice(question: "Q?", inspect: "`x`", criteria: %{"" => ""})
      end
    end
  end

  describe "encode/1" do
    test "encodes a noul question to Jev wire JSON" do
      question =
        Question.noul(
          question: "Is this true?",
          inspect: "`x`",
          true: %{what: "yes", examples: ["a"]},
          false: "no"
        )

      assert Question.encode(question) == %{
               "type" => "noul",
               "instructions" => %{"question" => "Is this true?", "inspect" => "`x`"},
               "criteria" => %{
                 "true" => %{"what" => "yes", "examples" => ["a"]},
                 "false" => %{"what" => "no"}
               }
             }
    end

    test "encodes score and choice questions" do
      score =
        Question.score(question: "How bad?", inspect: "`x`", criteria: ["low", "high"])

      assert Question.encode(score)["type"] == "score"
      assert Question.encode(score)["criteria"] == ["low", "high"]

      choice =
        Question.choice(
          question: "Which?",
          inspect: "`x`",
          criteria: %{"a" => "A", "b" => "B"}
        )

      assert Question.encode(choice)["type"] == "choice"
      assert Question.encode(choice)["criteria"]["a"] == "A"
    end

    test "raises on non-question" do
      assert_raise ArgumentError, ~r/Cite.Question/, fn ->
        Question.encode(%{type: :noul})
      end
    end
  end

  describe "focus" do
    test "is optional, rides under instructions when given, and must be a non-empty binary" do
      plain = Question.score(question: "S?", inspect: "`x`", criteria: ["a", "b"])
      refute Map.has_key?(Question.encode(plain)["instructions"], "focus")

      focused =
        Question.score(
          question: "S?",
          inspect: "`x`",
          criteria: ["a", "b"],
          focus: "Judge sense, not humour."
        )

      assert Question.encode(focused)["instructions"]["focus"] == "Judge sense, not humour."

      assert_raise ArgumentError, ~r/focus must be a non-empty binary/, fn ->
        Question.noul(question: "Q?", inspect: "`x`", true: "y", false: "n", focus: "")
      end
    end
  end
end
