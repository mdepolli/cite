defmodule CiteTest do
  use ExUnit.Case, async: true

  alias Cite.{Citation, Error, Finding, Passage, Report}
  alias Cite.TestPolicies.{Household, Riddles}

  # A stub client that answers every question: Nouls from `nouls` by key
  # (0.1 otherwise), Scores and Choices with fixed confident answers.
  defp client(nouls) do
    fn %{"questions" => questions} ->
      answers = Map.new(questions, fn {key, question} -> {key, answer(key, question, nouls)} end)

      {:ok,
       %{answers: answers, usage: %{input_tokens: 10, output_tokens: 0}, model: "jev-1.13.0"}}
    end
  end

  defp answer(key, %{"type" => "noul"}, nouls), do: %{"noul" => Map.get(nouls, key, 0.1)}
  defp answer(_key, %{"type" => "score"}, _nouls), do: %{"score" => 1.0, "confidence" => 0.9}

  defp answer(_key, %{"type" => "choice"}, _nouls),
    do: %{"choice" => "persistent", "confidence" => 0.9}

  # A client that reports each screening window it is sent, read off the
  # question keys ("<id>:riddle"), refuses the windows `too_large?` picks as
  # too large, and answers the rest with 0.1, so nothing matches.
  defp window_client(too_large?) do
    test_pid = self()
    answering = client(%{})

    fn %{"questions" => questions} = request ->
      window =
        questions
        |> Map.keys()
        |> Enum.map(&hd(String.split(&1, ":")))
        |> Enum.sort()

      send(test_pid, {:window, window})

      if too_large?.(window), do: {:error, :request_too_large}, else: answering.(request)
    end
  end

  # Every window the window client was sent, in order.
  defp windows_sent do
    receive do
      {:window, window} -> [window | windows_sent()]
    after
      0 -> []
    end
  end

  defp refusing_client do
    fn _request -> flunk("no request should be sent") end
  end

  describe "judge/4" do
    test "screens, gathers, and judges a riddle end to end" do
      # Arrange
      source = Cite.source(["Why is a raven like a writing-desk?", "Take some more tea."])
      client = client(%{"P000:riddle" => 0.94, "fit:P000" => 0.9})

      # Act
      report = Cite.judge(client, source, Riddles)

      # Assert
      assert report == %Report{
               findings: [
                 %Finding{
                   concern: :riddle,
                   category: :riddle,
                   verdict: :holds,
                   checks: %{},
                   descriptors: %{},
                   evidence: [
                     %Citation{
                       passage: %Passage{id: "P000", text: "Why is a raven like a writing-desk?"},
                       verdict: :holds,
                       answer: %{"noul" => 0.9}
                     }
                   ],
                   dropped: [],
                   over_cap: []
                 }
               ],
               screen: %{"P000" => %{riddle: 0.94}, "P001" => %{riddle: 0.1}},
               errors: [],
               usage: %{input_tokens: 20, output_tokens: 0},
               models: ["jev-1.13.0"]
             }
    end

    test "builds the household finding from factors" do
      # Arrange
      source =
        Cite.source(
          [
            %{id: "U3", text: "Two kids.", meta: %{speaker: "B"}},
            %{id: "U9", text: "Sixty a year.", meta: %{speaker: "B"}}
          ],
          as: "utterances",
          show: [:speaker]
        )

      client =
        client(%{
          "U3:client_speaking" => 0.9,
          "U9:client_speaking" => 0.9,
          "U3:dependents" => 0.9,
          "U9:primary_income" => 0.9,
          "same_household" => 0.9,
          "concentrated_income" => 0.9
        })

      # Act
      %Report{findings: findings} = Cite.judge(client, source, Household)

      # Assert
      assert Enum.map(
               findings,
               &{&1.concern, &1.verdict, Enum.map(&1.evidence, fn c -> c.passage.id end)}
             ) ==
               [{:household_income, :holds, ["U3", "U9"]}]
    end

    test "halves a round-1 window the provider refuses as too large" do
      # Arrange
      source = Cite.source(["a", "b", "c", "d"])
      client = window_client(&(length(&1) > 2))

      # Act
      report = Cite.judge(client, source, Riddles, window: 4)

      # Assert
      assert windows_sent() == [
               ["P000", "P001", "P002", "P003"],
               ["P000", "P001"],
               ["P002", "P003"]
             ]

      assert {report.errors, map_size(report.screen)} == {[], 4}
    end

    test "records a lone passage over the cap as an error, and still screens its siblings" do
      # Arrange
      source = Cite.source(["a", "b", "c", "d"])
      client = window_client(&("P001" in &1))

      # Act
      report = Cite.judge(client, source, Riddles, window: 4)

      # Assert
      assert windows_sent() == [
               ["P000", "P001", "P002", "P003"],
               ["P000", "P001"],
               ["P000"],
               ["P001"],
               ["P002", "P003"]
             ]

      assert report.errors == [
               %Error{concern: nil, passage_ids: ["P001"], reason: :request_too_large}
             ]

      assert Enum.sort(Map.keys(report.screen)) == ["P000", "P002", "P003"]
    end

    test "records every passage as its own error when each alone is over the cap" do
      # Arrange
      source = Cite.source(["a", "b", "c", "d"])
      client = window_client(fn _window -> true end)

      # Act
      report = Cite.judge(client, source, Riddles, window: 4)

      # Assert
      assert length(windows_sent()) == 7

      assert report.errors == [
               %Error{concern: nil, passage_ids: ["P000"], reason: :request_too_large},
               %Error{concern: nil, passage_ids: ["P001"], reason: :request_too_large},
               %Error{concern: nil, passage_ids: ["P002"], reason: :request_too_large},
               %Error{concern: nil, passage_ids: ["P003"], reason: :request_too_large}
             ]
    end

    test "a round-2 request refused as too large is that finding's error, sent once and not split" do
      # Arrange
      source = Cite.source(["Why is a raven like a writing-desk?", "Riddle me this?"])
      screening = client(%{"P000:riddle" => 0.9, "P001:riddle" => 0.9})
      test_pid = self()

      client = fn
        %{"questions" => %{"fit:P000" => _} = questions} ->
          send(test_pid, {:round_2, Enum.sort(Map.keys(questions))})
          {:error, :request_too_large}

        request ->
          screening.(request)
      end

      # Act
      report = Cite.judge(client, source, Riddles)

      # Assert
      assert_received {:round_2, ["fit:P000", "fit:P001"]}
      refute_received {:round_2, _}

      assert {report.findings, report.errors} ==
               {[],
                [
                  %Error{
                    concern: :riddle,
                    passage_ids: ["P000", "P001"],
                    reason: :request_too_large
                  }
                ]}
    end

    test "a reply missing an answer fails its whole request" do
      # Arrange
      source = Cite.source(["Why is a raven like a writing-desk?"])
      client = fn _request -> {:ok, %{answers: %{}, usage: nil}} end

      # Act
      report = Cite.judge(client, source, Riddles)

      # Assert
      assert {report.screen, report.errors} ==
               {%{},
                [
                  %Error{
                    concern: nil,
                    passage_ids: ["P000"],
                    reason: {:missing_answers, ["P000:riddle"]}
                  }
                ]}
    end

    test "a reply answering in the wrong shape fails its whole request" do
      # Arrange
      source = Cite.source(["a"])

      client = fn _request ->
        {:ok, %{answers: %{"P000:riddle" => %{"noul" => "high"}}, usage: nil}}
      end

      # Act
      report = Cite.judge(client, source, Riddles)

      # Assert
      assert report.errors == [
               %Error{
                 concern: nil,
                 passage_ids: ["P000"],
                 reason: {:malformed_answers, ["P000:riddle"]}
               }
             ]
    end

    test "an empty source sends no request and reports nothing" do
      assert Cite.judge(refusing_client(), Cite.source([]), Riddles) == %Report{
               findings: [],
               screen: %{},
               errors: [],
               usage: nil,
               models: []
             }
    end

    test "raises on a module that is not a policy, before any request" do
      assert_raise ArgumentError, ~r/Enum is not a Cite policy/, fn ->
        Cite.judge(refusing_client(), Cite.source(["a"]), Enum)
      end
    end

    test "raises on unknown or invalid options, before any request" do
      for opts <- [
            [review_band: {0.6, 0.4}],
            [max_evidence: 0],
            [window: 0],
            [threshold: "high"],
            [colour: :red]
          ] do
        assert_raise ArgumentError, fn ->
          Cite.judge(refusing_client(), Cite.source(["a"]), Riddles, opts)
        end
      end
    end

    test "raises when the client returns something that is not a verdict" do
      assert_raise ArgumentError, ~r/client must return/, fn ->
        Cite.judge(fn _request -> :ok end, Cite.source(["a"]), Riddles)
      end
    end
  end

  test "a report encodes with Jason" do
    report = Cite.judge(client(%{}), Cite.source(["a"]), Riddles)

    assert Jason.decode!(Jason.encode!(report)) == %{
             "findings" => [],
             "screen" => %{"P000" => %{"riddle" => 0.1}},
             "errors" => [],
             "usage" => %{"input_tokens" => 10, "output_tokens" => 0},
             "models" => ["jev-1.13.0"]
           }
  end
end
