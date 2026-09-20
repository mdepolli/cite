defmodule Cite.SelectTest do
  use ExUnit.Case, async: true

  alias Cite.{Candidate, Cluster, Error, Question, Result, Select, Span}

  defp noul_q(text) do
    Question.noul(
      question: text,
      inspect: ["candidates"],
      true: "yes",
      false: "no"
    )
  end

  defp household_fixture do
    source = "Four kids at home. I make about 180000 a year."

    candidates = [
      %Candidate{
        id: "U000",
        text: "Four kids at home.",
        byte_start: 0,
        byte_end: 18,
        meta: %{speaker: "A"}
      },
      %Candidate{
        id: "U001",
        text: "I make about 180000 a year.",
        byte_start: 19,
        byte_end: 46,
        meta: %{speaker: "B"}
      }
    ]

    {source, candidates}
  end

  defp scan_noul("U000:dependents"), do: 0.9
  defp scan_noul("U001:primary_income"), do: 0.9
  defp scan_noul(_key), do: 0.1

  defp best(index, atomic) do
    index
    |> Enum.filter(fn {_id, scores} -> Map.get(scores, atomic, 0) > 0.5 end)
    |> Enum.max_by(fn {_id, scores} -> scores[atomic] end, fn -> nil end)
    |> case do
      nil -> nil
      {id, _scores} -> id
    end
  end

  defp household_spec do
    %{
      atomics: [
        %{
          name: "dependents",
          question: fn %Candidate{id: id} ->
            noul_q("Does candidate #{id} mention dependents?")
          end
        },
        %{
          name: "primary_income",
          question: fn %Candidate{id: id} ->
            noul_q("Does candidate #{id} state primary income?")
          end
        }
      ],
      compose: fn index, candidates ->
        by_id = Map.new(candidates, &{&1.id, &1})
        dep_id = best(index, "dependents")
        inc_id = best(index, "primary_income")

        if dep_id && inc_id && dep_id != inc_id do
          dep = by_id[dep_id]
          inc = by_id[inc_id]

          [
            Cluster.new(
              id: "household",
              class: "resilience",
              members: [dep, inc],
              state: %{household: dep, income: inc},
              questions: %{
                "fits" =>
                  noul_q(
                    "Taken together, do household and income describe income concentrated on one earner?"
                  ),
                "severity" =>
                  Question.score(
                    question: "How severe?",
                    inspect: ["household", "income"],
                    criteria: ["coping", "needs support", "cannot decide"]
                  ),
                "temporal" =>
                  Question.choice(
                    question: "Transient or lasting?",
                    inspect: ["household", "income"],
                    criteria: %{
                      "transient" => "recovers",
                      "persistent" => "lasting",
                      "unknown" => "unclear"
                    }
                  )
              }
            )
          ]
        else
          []
        end
      end
    }
  end

  describe "select/5 compose" do
    test "emits one span per cluster member after a compare Noul fires" do
      # Arrange
      {source, candidates} = household_fixture()

      judge = fn request ->
        questions = request["questions"]

        answers =
          if Map.has_key?(questions, "fits") do
            %{
              "fits" => %{"noul" => 0.86},
              "severity" => %{"score" => 0.2, "confidence" => 0.9},
              "temporal" => %{"choice" => "transient", "confidence" => 0.9}
            }
          else
            # Scan: meta (speaker) must be on the wire under candidates.
            candidates_state = request["state"]["candidates"]
            assert candidates_state["U000"]["speaker"] == "A"
            assert candidates_state["U000"]["text"] == "Four kids at home."

            Map.new(questions, fn {key, _} -> {key, %{"noul" => scan_noul(key)}} end)
          end

        {:ok, %{answers: answers, usage: %{input_tokens: 3, output_tokens: 0}}}
      end

      # Act
      result = Select.select(judge, source, candidates, household_spec())

      # Assert
      assert %Result{errors: []} = result
      texts = Enum.sort(Enum.map(result.spans, & &1.text))

      assert texts == ["Four kids at home.", "I make about 180000 a year."]
      assert Enum.all?(result.spans, &(&1.class == "resilience"))

      assert Enum.all?(result.spans, fn %Span{attributes: attrs} ->
               attrs["cluster_id"] == "household" and
                 attrs["severity"] == 0 and
                 attrs["temporal"] == "transient" and
                 attrs["review"] == false
             end)

      assert result.scan == %{
               "U000" => %{"dependents" => 0.9, "primary_income" => 0.1},
               "U001" => %{"dependents" => 0.1, "primary_income" => 0.9}
             }

      assert result.usage == %{input_tokens: 6, output_tokens: 0}
    end

    test "windows atomic scan so each request stays within window_size" do
      # Arrange
      {source, candidates} = household_fixture()
      parent = self()

      judge = fn request ->
        keys = Map.keys(request["questions"])
        send(parent, {:scan, keys})
        answers = Map.new(keys, fn key -> {key, %{"noul" => 0.1}} end)
        {:ok, %{answers: answers, usage: nil}}
      end

      # Act
      Select.select(judge, source, candidates, household_spec(), window_size: 1)

      # Assert
      assert_receive {:scan, keys1}
      assert_receive {:scan, keys2}
      assert length(keys1) == 2
      assert length(keys2) == 2

      assert Enum.sort(keys1 ++ keys2) == [
               "U000:dependents",
               "U000:primary_income",
               "U001:dependents",
               "U001:primary_income"
             ]
    end

    test "splits a scan window that exceeds the request token cap" do
      # Arrange
      {source, candidates} = household_fixture()
      parent = self()

      judge = fn request ->
        ids =
          request["state"]
          |> Map.get("candidates", %{})
          |> Map.keys()
          |> Enum.sort()

        send(parent, {:scan, ids})

        cond do
          length(ids) > 1 ->
            {:error, {:bad_request, "max_tokens_exceeded"}}

          Map.has_key?(request["questions"], "fits") ->
            {:ok, %{answers: %{"fits" => %{"noul" => 0.2}}, usage: nil}}

          true ->
            answers =
              Map.new(request["questions"], fn {key, _} ->
                {key, %{"noul" => scan_noul(key)}}
              end)

            {:ok, %{answers: answers, usage: nil}}
        end
      end

      # Act
      result = Select.select(judge, source, candidates, household_spec())

      # Assert
      assert_receive {:scan, ["U000", "U001"]}
      assert_receive {:scan, ["U000"]}
      assert_receive {:scan, ["U001"]}
      assert result.errors == []

      assert result.scan == %{
               "U000" => %{"dependents" => 0.9, "primary_income" => 0.1},
               "U001" => %{"dependents" => 0.1, "primary_income" => 0.9}
             }
    end

    test "skips the compare call when the cluster has no questions" do
      # Arrange
      source = "Four kids at home."
      parent = self()
      candidate = %Candidate{id: "U000", text: "Four kids at home.", byte_start: 0, byte_end: 18}

      spec = %{
        atomics: [
          %{
            name: "dependents",
            question: fn %Candidate{id: id} ->
              noul_q("Does candidate #{id} mention dependents?")
            end
          }
        ],
        compose: fn index, candidates ->
          if match?(%{"U000" => %{"dependents" => _}}, index) do
            [
              Cluster.new(
                id: "solo",
                class: "resilience",
                members: candidates,
                state: %{},
                questions: %{}
              )
            ]
          else
            []
          end
        end
      }

      judge = fn request ->
        keys = Map.keys(request["questions"])
        send(parent, {:call, keys})
        answers = Map.new(keys, fn key -> {key, %{"noul" => 0.9}} end)
        {:ok, %{answers: answers, usage: nil}}
      end

      # Act
      result = Select.select(judge, source, [candidate], spec)

      # Assert
      assert_receive {:call, keys}
      refute_receive {:call, _}
      assert keys == ["U000:dependents"]
      assert [%Span{class: "resilience", text: "Four kids at home."}] = result.spans
    end

    test "raises when compose returns a member not in candidates" do
      # Arrange
      {source, candidates} = household_fixture()
      stranger = %Candidate{id: "UX", text: "nope", byte_start: 0, byte_end: 4}

      spec = %{
        atomics: [
          %{name: "dependents", question: fn _ -> noul_q("d?") end}
        ],
        compose: fn _index, _candidates ->
          [
            Cluster.new(
              id: "bad",
              class: "resilience",
              members: [stranger],
              state: %{},
              questions: %{}
            )
          ]
        end
      }

      judge = fn request ->
        answers =
          Map.new(request["questions"], fn {key, _} -> {key, %{"noul" => 0.9}} end)

        {:ok, %{answers: answers, usage: nil}}
      end

      # Act + Assert
      assert_raise ArgumentError, ~r/member "UX" is not in candidates/, fn ->
        Select.select(judge, source, candidates, spec)
      end
    end

    test "records a scan error when a single candidate still exceeds the token cap" do
      # Arrange
      source = "Four kids at home."
      candidate = %Candidate{id: "U000", text: "Four kids at home.", byte_start: 0, byte_end: 18}

      spec = %{
        atomics: [%{name: "dependents", question: fn _ -> noul_q("d?") end}],
        compose: fn _, _ -> [] end
      }

      judge = fn _request -> {:error, {:bad_request, "max_tokens_exceeded"}} end

      # Act
      result = Select.select(judge, source, [candidate], spec)

      # Assert
      assert [
               %Error{
                 byte_start: 0,
                 byte_end: 18,
                 reason: {:bad_request, "max_tokens_exceeded"}
               }
             ] =
               result.errors

      assert result.spans == []
    end

    test "raises on duplicate cluster ids from compose" do
      # Arrange
      {source, candidates} = household_fixture()
      [first | _] = candidates

      spec = %{
        atomics: [%{name: "dependents", question: fn _ -> noul_q("d?") end}],
        compose: fn _index, _candidates ->
          cluster =
            Cluster.new(
              id: "dup",
              class: "resilience",
              members: [first],
              state: %{},
              questions: %{}
            )

          [cluster, cluster]
        end
      }

      judge = fn request ->
        answers = Map.new(request["questions"], fn {key, _} -> {key, %{"noul" => 0.9}} end)
        {:ok, %{answers: answers, usage: nil}}
      end

      # Act + Assert
      assert_raise ArgumentError, ~r/duplicate cluster ids/, fn ->
        Select.select(judge, source, candidates, spec)
      end
    end

    test "raises on duplicate candidate ids" do
      # Arrange
      candidates = [
        %Candidate{id: "U000", text: "aaaa", byte_start: 0, byte_end: 4},
        %Candidate{id: "U000", text: "bbbb", byte_start: 5, byte_end: 9}
      ]

      spec = %{atomics: [], compose: fn _, _ -> [] end}

      # Act + Assert
      assert_raise ArgumentError, ~r/candidate ids must be unique, duplicated: \["U000"\]/, fn ->
        Select.select(
          fn _ -> {:ok, %{answers: %{}, usage: nil}} end,
          "aaaa bbbb",
          candidates,
          spec
        )
      end
    end

    test "raises on unknown options" do
      # Arrange
      spec = %{atomics: [], compose: fn _, _ -> [] end}

      # Act + Assert
      assert_raise ArgumentError, ~r/unknown keys \[:confidence_flor\]/, fn ->
        Select.select(fn _ -> {:ok, %{answers: %{}, usage: nil}} end, "", [], spec,
          confidence_flor: 0.9
        )
      end
    end
  end
end
