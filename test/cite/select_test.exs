defmodule Cite.SelectTest do
  use ExUnit.Case, async: true

  alias Cite.{Candidate, Cluster, Error, Question, Result, Span}
  alias Cite.Wire.Object

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
    test "runs scan, compose, compare, and emit end to end" do
      # Arrange
      {source, candidates} = household_fixture()

      judge = fn request ->
        questions = request["questions"]

        answers =
          if Map.has_key?(questions, "fits"),
            do: compare_answers(questions, 0.86),
            else: Map.new(questions, fn {key, _} -> {key, %{"noul" => scan_noul(key)}} end)

        {:ok, %{answers: answers, usage: %{input_tokens: 3, output_tokens: 0}}}
      end

      # Act
      result = Cite.select(judge, source, candidates, household_spec())

      # Assert
      assert %Result{errors: [], rejected: %{}} = result
      assert Enum.sort(Enum.map(result.spans, & &1.candidate_id)) == ["U000", "U001"]
      assert Enum.sort(Map.keys(result.scan)) == ["U000", "U001"]
      assert result.usage == %{input_tokens: 6, output_tokens: 0}
    end

    test "collects compare errors into Result.errors" do
      # Arrange
      {source, candidates} = household_fixture()

      judge = fn request ->
        if Map.has_key?(request["questions"], "fits"),
          do: {:error, :compare_down},
          else:
            {:ok,
             %{
               answers:
                 Map.new(request["questions"], fn {key, _} ->
                   {key, %{"noul" => scan_noul(key)}}
                 end),
               usage: nil
             }}
      end

      # Act
      result = Cite.select(judge, source, candidates, household_spec())

      # Assert
      assert result.spans == []
      assert [%Error{byte_start: 0, byte_end: 46, reason: :compare_down}] = result.errors
      assert result.usage == nil
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
      Cite.select(judge, source, candidates, household_spec(), window_size: 1)

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
          |> Map.get("candidates")
          |> then(fn
            %Object{pairs: pairs} -> Enum.map(pairs, &elem(&1, 0))
            nil -> []
          end)

        send(parent, {:scan, ids})

        cond do
          length(ids) > 1 ->
            {:error, :request_too_large}

          Map.has_key?(request["questions"], "fits") ->
            {:ok, %{answers: compare_answers(request["questions"], 0.2), usage: nil}}

          true ->
            answers =
              Map.new(request["questions"], fn {key, _} ->
                {key, %{"noul" => scan_noul(key)}}
              end)

            {:ok, %{answers: answers, usage: nil}}
        end
      end

      # Act
      result = Cite.select(judge, source, candidates, household_spec())

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
      result = Cite.select(judge, source, [candidate], spec)

      # Assert
      assert_receive {:call, keys}
      refute_receive {:call, _}
      assert keys == ["U000:dependents"]
      assert [%Span{class: "resilience", text: "Four kids at home."}] = result.spans
    end

    test "records a scan error when a single candidate still exceeds the token cap" do
      # Arrange
      source = "Four kids at home."
      candidate = %Candidate{id: "U000", text: "Four kids at home.", byte_start: 0, byte_end: 18}

      spec = %{
        atomics: [%{name: "dependents", question: fn _ -> noul_q("d?") end}],
        compose: fn _, _ -> [] end
      }

      judge = fn _request -> {:error, :request_too_large} end

      # Act
      result = Cite.select(judge, source, [candidate], spec)

      # Assert
      assert [
               %Error{
                 byte_start: 0,
                 byte_end: 18,
                 reason: :request_too_large
               }
             ] =
               result.errors

      assert result.spans == []
    end

    test "stops splitting once a single candidate is too large; siblings are errors without a call" do
      # Arrange — 16 candidates, every request refused as too large.
      candidates =
        for i <- 0..15 do
          %Candidate{id: "U#{i}", text: "x", byte_start: i * 2, byte_end: i * 2 + 1}
        end

      source = Enum.map_join(candidates, " ", & &1.text)

      spec = %{
        atomics: [%{name: "d", question: fn _ -> noul_q("d?") end}],
        compose: fn _, _ -> [] end
      }

      {:ok, calls} = Agent.start_link(fn -> 0 end)

      client = fn _ ->
        Agent.update(calls, &(&1 + 1))
        {:error, :request_too_large}
      end

      # Act
      result = Cite.select(client, source, candidates, spec, window_size: 16)

      # Assert — 16 → 8 → 4 → 2 → 1 is five calls; every right sibling is skipped.
      assert Agent.get(calls, & &1) == 5
      assert Enum.all?(result.errors, &(&1.reason == :request_too_large))

      assert result.errors |> Enum.flat_map(& &1.candidate_ids) |> Enum.sort() ==
               Enum.sort(Enum.map(candidates, & &1.id))

      assert result.scan == %{}
    end

    test "no candidates means no calls and an empty result" do
      spec = %{
        atomics: [%{name: "d", question: fn _ -> noul_q("d?") end}],
        compose: fn _, _ -> [] end
      }

      judge = fn _ -> flunk("judge was called with nothing to judge") end

      assert %Result{spans: [], errors: [], usage: nil, models: [], scan: %{}, rejected: %{}} =
               Cite.select(judge, "", [], spec)
    end

    test "checks candidates against the source before any judge call" do
      spec = %{
        atomics: [%{name: "d", question: fn _ -> noul_q("d?") end}],
        compose: fn _, _ -> [] end
      }

      judge = fn _ -> flunk("judge was called before candidates were checked") end
      stale = [%Candidate{id: "U0", text: "aaaa", byte_start: 0, byte_end: 4}]

      assert_raise ArgumentError, ~r/text does not match source/, fn ->
        Cite.select(judge, "bbbb", stale, spec)
      end
    end

    test "records a reply that skips a question as an error, not as no" do
      # Arrange — the scan stub answers only one of the two candidates' questions.
      {source, candidates} = household_fixture()

      client = fn %{"questions" => questions} ->
        [first | _] = questions |> Map.keys() |> Enum.sort()
        {:ok, %{answers: %{first => %{"noul" => 0.9}}, usage: nil}}
      end

      # Act
      result = Cite.select(client, source, candidates, household_spec())

      # Assert
      assert result.scan == %{}
      assert [%Error{reason: {:missing_answers, missing}}] = result.errors
      assert length(missing) == 3
    end

    test "records every model that answered, once each, and rejects a bad model" do
      {source, candidates} = household_fixture()

      spec = %{
        atomics: [%{name: "d", question: fn _ -> noul_q("d?") end}],
        compose: fn _, _ -> [] end
      }

      client = fn %{"questions" => qs} ->
        {:ok,
         %{
           answers: Map.new(qs, fn {k, _} -> {k, %{"noul" => 0.1}} end),
           usage: nil,
           model: "jev-1.13.0"
         }}
      end

      assert Cite.select(client, source, candidates, spec).models == ["jev-1.13.0"]

      assert Cite.select(
               fn q ->
                 {:ok, %{answers: Map.new(q["questions"], fn {k, _} -> {k, %{}} end), usage: nil}}
               end,
               source,
               candidates,
               spec
             ).models == []

      assert_raise ArgumentError, ~r/client model must be a non-empty binary/, fn ->
        Cite.select(
          fn _ -> {:ok, %{answers: %{}, usage: nil, model: ""}} end,
          source,
          candidates,
          spec
        )
      end
    end

    test "records a reply with a malformed answer as an error, not as no" do
      {source, candidates} = household_fixture()

      client = fn %{"questions" => qs} ->
        answers = Map.new(qs, fn {k, _} -> {k, %{"noul" => 0.9}} end)
        [first | _] = answers |> Map.keys() |> Enum.sort()
        {:ok, %{answers: Map.put(answers, first, %{"noul" => "high"}), usage: nil}}
      end

      result = Cite.select(client, source, candidates, household_spec())

      assert result.scan == %{}
      assert [%Error{reason: {:malformed_answers, [_]}}] = result.errors
    end

    test "raises when the client returns the wrong shape, including a bad usage" do
      spec = %{
        atomics: [%{name: "d", question: fn _ -> noul_q("d?") end}],
        compose: fn _, _ -> [] end
      }

      {source, candidates} = household_fixture()

      for bad <- [
            {:ok, %{}},
            {:ok, %{answers: []}},
            {:ok, %{answers: %{}}},
            :done,
            %{answers: %{}}
          ] do
        assert_raise ArgumentError, ~r/client must return/, fn ->
          Cite.select(fn _ -> bad end, source, candidates, spec)
        end
      end

      for usage <- [
            "lots",
            %{"input_tokens" => 1, "output_tokens" => 1},
            %{input_tokens: -1, output_tokens: 0}
          ] do
        assert_raise ArgumentError, ~r/client usage must be nil or/, fn ->
          Cite.select(fn _ -> {:ok, %{answers: %{}, usage: usage}} end, source, candidates, spec)
        end
      end
    end

    test "raises before any call when an atomic builds a Score instead of a Noul" do
      {source, candidates} = household_fixture()
      score = fn _ -> Question.score(question: "S?", inspect: "`x`", criteria: ["a", "b"]) end
      spec = %{atomics: [%{name: "sev", question: score}], compose: fn _, _ -> [] end}
      client = fn _ -> flunk("judge was called with a non-Noul atomic") end

      assert_raise ArgumentError, ~r/atomic "sev" must build a Noul question, got a :score/, fn ->
        Cite.select(client, source, candidates, spec)
      end
    end

    test "raises on malformed atomics before any judge call" do
      judge = fn _ -> flunk("judge was called with bad atomics") end
      {source, candidates} = household_fixture()
      question = fn _ -> noul_q("?") end

      for {atomics, message} <- [
            {[], ~r/non-empty list/},
            {[%{name: :dependents, question: question}], ~r/non-empty binary/},
            {[%{name: "d", question: fn -> nil end}], ~r/fun\/1/},
            {[%{name: "b:c", question: question}], ~r/must not contain ":"/},
            {[%{name: "d", question: question}, %{name: "d", question: question}],
             ~r/duplicated: \["d"\]/}
          ] do
        assert_raise ArgumentError, message, fn ->
          Cite.select(judge, source, candidates, %{atomics: atomics, compose: fn _, _ -> [] end})
        end
      end
    end

    test "raises when the caller's state uses the scan's candidates key" do
      spec = %{
        atomics: [%{name: "d", question: fn _ -> noul_q("d?") end}],
        compose: fn _, _ -> [] end
      }

      client = fn _ -> {:ok, %{answers: %{}, usage: nil}} end

      for state <- [%{"candidates" => 1}, %{candidates: 1}] do
        assert_raise ArgumentError, ~r/must not use the "candidates" key/, fn ->
          Cite.select(client, "", [], spec, state: state)
        end
      end
    end

    test "spec.scan_key names the state key the window sits under" do
      {source, candidates} = household_fixture()

      spec = %{
        atomics: [%{name: "d", question: fn _ -> noul_q("d?") end}],
        compose: fn _, _ -> [] end
      }

      parent = self()

      client = fn %{"state" => state, "questions" => qs} ->
        send(parent, {:state_keys, Map.keys(state)})
        {:ok, %{answers: Map.new(qs, fn {k, _} -> {k, %{"noul" => 0.1}} end), usage: nil}}
      end

      Cite.select(client, source, candidates, Map.put(spec, :scan_key, "utterances"))
      assert_receive {:state_keys, ["utterances"]}

      assert_raise ArgumentError, ~r/must not use the "utterances" key/, fn ->
        Cite.select(client, source, candidates, Map.put(spec, :scan_key, "utterances"),
          state: %{"utterances" => 1}
        )
      end

      assert_raise ArgumentError, ~r/spec.scan_key must be a non-empty binary/, fn ->
        Cite.select(client, source, candidates, Map.put(spec, :scan_key, ""))
      end
    end

    test "raises on option values that cannot work" do
      spec = %{
        atomics: [%{name: "d", question: fn _ -> noul_q("d?") end}],
        compose: fn _, _ -> [] end
      }

      judge = fn _ -> {:ok, %{answers: %{}, usage: nil}} end

      for bad <- [
            [window_size: 0],
            [review_band: {0.6, 0.4}],
            [review_band: {0.5, 0.5}],
            [confidence_floor: "high"],
            [state: URI.parse("x")]
          ] do
        assert_raise ArgumentError, ~r/invalid options/, fn ->
          Cite.select(judge, "", [], spec, bad)
        end
      end
    end

    test "raises on unknown options" do
      # Arrange
      spec = %{
        atomics: [%{name: "d", question: fn _ -> noul_q("d?") end}],
        compose: fn _, _ -> [] end
      }

      # Act + Assert
      assert_raise ArgumentError, ~r/unknown keys \[:confidence_flor\]/, fn ->
        Cite.select(fn _ -> {:ok, %{answers: %{}, usage: nil}} end, "", [], spec,
          confidence_flor: 0.9
        )
      end
    end
  end

  # Every question answered, by type; the Noul at `fits` gets `noul`.
  defp compare_answers(questions, noul) do
    Map.new(questions, fn
      {key, %{"type" => "noul"}} ->
        {key, %{"noul" => noul}}

      {key, %{"type" => "score"}} ->
        {key, %{"score" => 1, "confidence" => 0.9}}

      {key, %{"type" => "choice", "criteria" => c}} ->
        {key, %{"choice" => c |> Map.keys() |> hd(), "confidence" => 0.9}}
    end)
  end
end
