defmodule CiteTest do
  use ExUnit.Case, async: true

  alias Cite.{Citation, Error, Finding, Passage, Report}
  alias Cite.TestPolicies.{Household, Riddles, TwoConcerns}

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

  # The ids of the passages a round-1 request screens, read off its question
  # keys ("<id>:riddle").
  defp window_ids(%{"questions" => questions}) do
    questions
    |> Map.keys()
    |> Enum.map(&hd(String.split(&1, ":")))
    |> Enum.uniq()
    |> Enum.sort()
  end

  # A client that reports each screening window it is sent, refuses the
  # windows `too_large?` picks as too large, and answers the rest with 0.1,
  # so nothing matches.
  defp window_client(too_large?) do
    test_pid = self()
    answering = client(%{})

    fn request ->
      window = window_ids(request)
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

  # A client that reports each request it holds to the test process as
  # {:arrive, label, pid} and answers only when the test sends pid :go.
  # Requests `label` maps to nil are answered at once.
  defp held_client(label, answering) do
    test_pid = self()

    fn request ->
      case label.(request) do
        nil ->
          answering.(request)

        held ->
          send(test_pid, {:arrive, held, self()})

          receive do
            :go -> answering.(request)
          end
      end
    end
  end

  # Runs Cite.judge/4 in a task so the test process is free to pace the
  # client.
  defp judge_async(client, source, policy, opts) do
    Task.async(fn -> Cite.judge(client, source, policy, opts) end)
  end

  defp arrivals(n) do
    for _ <- 1..n//1 do
      assert_receive {:arrive, label, pid}
      {label, pid}
    end
  end

  defp release(arrivals), do: Enum.each(arrivals, fn {_label, pid} -> send(pid, :go) end)

  # Judges eight passages at window 1 and concurrency 4, holding every
  # request. P001's client calls `failing` in place of a reply; `catching`
  # runs the judge call in the caller task and returns what it failed with.
  # Releases P001 alone and waits for its task to go down, which frees a
  # slot. Returns the judge task and the three requests still held.
  defp fail_second_of_four(failing, catching) do
    source = Cite.source(["a", "b", "c", "d", "e", "f", "g", "h"])
    answering = client(%{})

    reply = fn request ->
      if window_ids(request) == ["P001"], do: failing.(), else: answering.(request)
    end

    client = held_client(&window_ids/1, reply)

    task =
      Task.async(fn ->
        catching.(fn -> Cite.judge(client, source, Riddles, window: 1, concurrency: 4) end)
      end)

    held = Map.new(arrivals(4))
    {second, others} = Map.pop(held, ["P001"])
    ref = Process.monitor(second)
    send(second, :go)
    assert_receive {:DOWN, ^ref, :process, ^second, _}

    {task, others}
  end

  describe "judge/4 end to end" do
    test "an empty source sends no request and reports nothing" do
      assert Cite.judge(refusing_client(), Cite.source([]), Riddles) == %Report{
               findings: [],
               screen: %{},
               errors: [],
               usage: nil,
               models: []
             }
    end

    test "screens, gathers, and judges a riddle end to end" do
      source = Cite.source(["Why is a raven like a writing-desk?", "Take some more tea."])
      client = client(%{"P000:riddle" => 0.94, "confirm:P000" => 0.9})

      assert Cite.judge(client, source, Riddles) == %Report{
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
                   dropped: []
                 }
               ],
               screen: %{"P000" => %{riddle: 0.94}, "P001" => %{riddle: 0.1}},
               errors: [],
               usage: %{input_tokens: 20, output_tokens: 0},
               models: ["jev-1.13.0"]
             }
    end

    test "builds the household finding from factors" do
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

      %Report{findings: findings} = Cite.judge(client, source, Household)

      assert Enum.map(
               findings,
               &{&1.concern, &1.verdict, Enum.map(&1.evidence, fn c -> c.passage.id end)}
             ) ==
               [{:household_income, :holds, ["U3", "U9"]}]
    end

    test "screens a concern directly through a filter, confirms it, and describes it" do
      source =
        Cite.source([%{id: "U1", text: "We're behind on the mortgage.", meta: %{speaker: "B"}}],
          as: "utterances",
          show: [:speaker]
        )

      client =
        client(%{"U1:client_speaking" => 0.9, "U1:cashflow_stress" => 0.9, "confirm:U1" => 0.9})

      assert Cite.judge(client, source, Household) == %Report{
               findings: [
                 %Finding{
                   concern: :cashflow_stress,
                   category: :resilience,
                   verdict: :holds,
                   checks: %{},
                   descriptors: %{
                     severity: %{"score" => 1.0, "confidence" => 0.9},
                     temporal: %{"choice" => "persistent", "confidence" => 0.9}
                   },
                   evidence: [
                     %Citation{
                       passage: %Passage{
                         id: "U1",
                         text: "We're behind on the mortgage.",
                         meta: %{speaker: "B"}
                       },
                       verdict: :holds,
                       answer: %{"noul" => 0.9}
                     }
                   ],
                   dropped: []
                 }
               ],
               screen: %{
                 "U1" => %{
                   client_speaking: 0.9,
                   cashflow_stress: 0.9,
                   dependents: 0.1,
                   primary_income: 0.1,
                   other_household_income: 0.1
                 }
               },
               errors: [],
               usage: %{input_tokens: 20, output_tokens: 0},
               models: ["jev-1.13.0"]
             }
    end

    test "screens in windows of the requested size, in source order" do
      source = Cite.source(["a", "b", "c", "d", "e"])

      Cite.judge(window_client(fn _window -> false end), source, Riddles,
        window: 2,
        concurrency: 1
      )

      assert windows_sent() == [["P000", "P001"], ["P002", "P003"], ["P004"]]
    end

    test "judges every match in one round-2 request, however many" do
      # Arrange
      source = Cite.source(Enum.map(1..25, &"Riddle number #{&1}?"))
      screening = client(Map.new(0..24, &{"P#{String.pad_leading("#{&1}", 3, "0")}:riddle", 0.9}))
      test_pid = self()

      client = fn
        %{"questions" => %{"confirm:P000" => _} = questions} = request ->
          send(test_pid, {:round_2, map_size(questions)})
          screening.(request)

        request ->
          screening.(request)
      end

      # Act
      %Report{findings: [finding]} = Cite.judge(client, source, Riddles)

      # Assert
      assert_received {:round_2, 25}
      refute_received {:round_2, _}
      # Every confirm answers the stub's default 0.1, so all 25 are dropped.
      assert {finding.evidence, length(finding.dropped), finding.verdict} == {[], 25, :fails}
    end
  end

  describe "judge/4 when the provider refuses a request as too large" do
    test "halves a round-1 window the provider refuses as too large" do
      # Arrange
      source = Cite.source(["a", "b", "c", "d"])
      client = window_client(&(length(&1) > 2))

      # Act
      report = Cite.judge(client, source, Riddles, window: 4, concurrency: 1)

      # Assert
      assert windows_sent() == [
               ["P000", "P001", "P002", "P003"],
               ["P000", "P001"],
               ["P002", "P003"]
             ]

      assert {report.errors, map_size(report.screen)} == {[], 4}
    end

    test "records each lone passage over the cap as an error, and still screens its siblings" do
      # Arrange
      source = Cite.source(["a", "b", "c", "d"])
      client = window_client(&("P001" in &1 or "P003" in &1))

      # Act
      report = Cite.judge(client, source, Riddles, window: 4, concurrency: 1)

      # Assert
      assert windows_sent() == [
               ["P000", "P001", "P002", "P003"],
               ["P000", "P001"],
               ["P000"],
               ["P001"],
               ["P002", "P003"],
               ["P002"],
               ["P003"]
             ]

      assert report.errors == [
               %Error{concern: nil, passage_ids: ["P001"], reason: :request_too_large},
               %Error{concern: nil, passage_ids: ["P003"], reason: :request_too_large}
             ]

      assert Enum.sort(Map.keys(report.screen)) == ["P000", "P002"]
    end

    test "a round-2 request refused as too large is that finding's error, sent once and not split" do
      # Arrange
      source = Cite.source(["Why is a raven like a writing-desk?", "Riddle me this?"])
      screening = client(%{"P000:riddle" => 0.9, "P001:riddle" => 0.9})
      test_pid = self()

      client = fn
        %{"questions" => %{"confirm:P000" => _} = questions} ->
          send(test_pid, {:round_2, Enum.sort(Map.keys(questions))})
          {:error, :request_too_large}

        request ->
          screening.(request)
      end

      # Act
      report = Cite.judge(client, source, Riddles)

      # Assert
      assert_received {:round_2, ["confirm:P000", "confirm:P001"]}
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
  end

  describe "judge/4 reading replies" do
    test "reports each model that answered once, in order of first answer, across rounds" do
      source = Cite.source(["Why is a raven like a writing-desk?", "Take some more tea."])
      screening = client(%{"P000:riddle" => 0.94})

      client = fn
        %{"questions" => %{"confirm:P000" => _}} = request ->
          {:ok, verdict} = screening.(request)
          {:ok, %{verdict | model: "jev-1.14.0"}}

        request ->
          screening.(request)
      end

      report = Cite.judge(client, source, Riddles, window: 1)

      assert report.models == ["jev-1.13.0", "jev-1.14.0"]
    end

    test "a reply missing an answer fails its whole request" do
      source = Cite.source(["Why is a raven like a writing-desk?"])
      client = fn _request -> {:ok, %{answers: %{}, usage: nil}} end
      report = Cite.judge(client, source, Riddles)

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
  end

  describe "judge/4 arguments" do
    test "raises on an argument it cannot use before any request" do
      assert_raise ArgumentError,
                   "invalid value for :window option: expected positive integer, got: 0",
                   fn -> Cite.judge(refusing_client(), Cite.source(["a"]), Riddles, window: 0) end
    end

    test "raises when the client returns something that is not a verdict" do
      for concurrency <- [1, 4],
          {reply, message} <- [
            {:ok,
             "client must return {:ok, %{answers: map, usage: map | nil}} or {:error, reason}, got: :ok"},
            {{:ok, %{answers: %{}, usage: :lots}},
             "client usage must be nil or %{input_tokens: n, output_tokens: n}, got: :lots"},
            {{:ok, %{answers: %{}, usage: nil, model: 123}},
             "client model must be a non-empty binary when given, got: 123"},
            {{:ok, %{answers: %{}, usage: nil, model: ""}},
             ~s(client model must be a non-empty binary when given, got: "")}
          ] do
        assert_raise RuntimeError, message, fn ->
          Cite.judge(fn _request -> reply end, Cite.source(["a"]), Riddles,
            concurrency: concurrency
          )
        end
      end
    end

    test "ends the run at a client's raise, sending nothing after it" do
      # Arrange
      test_pid = self()
      source = Cite.source(["Why is a raven like a writing-desk?", "b", "c"])
      answering = client(%{"P000:riddle" => 0.9})

      client = fn request ->
        window = window_ids(request)
        send(test_pid, {:window, window})
        if window == ["P001"], do: :not_a_verdict, else: answering.(request)
      end

      # Act + Assert
      assert_raise RuntimeError, ~r/got: :not_a_verdict/, fn ->
        Cite.judge(client, source, Riddles, window: 1, concurrency: 1)
      end

      # P000's riddle would have been judged in round 2.
      assert windows_sent() == [["P000"], ["P001"]]
    end

    test "refuses a concurrency that is not a positive integer" do
      for {bad, message} <- [
            {0, "invalid value for :concurrency option: expected positive integer, got: 0"},
            {:many,
             "invalid value for :concurrency option: expected positive integer, got: :many"}
          ] do
        assert_raise ArgumentError, message, fn ->
          Cite.judge(refusing_client(), Cite.source(["a"]), Riddles, concurrency: bad)
        end
      end
    end
  end

  describe "judge/4 with concurrency" do
    test "sends up to `concurrency` requests at once" do
      # Arrange
      source = Cite.source(["a", "b", "c", "d"])
      client = held_client(&window_ids/1, client(%{}))
      task = judge_async(client, source, Riddles, window: 1, concurrency: 4)

      # Act
      held = arrivals(4)
      release(held)

      # Assert
      assert Enum.sort(Enum.map(held, &elem(&1, 0))) == [["P000"], ["P001"], ["P002"], ["P003"]]
      assert %Report{errors: []} = Task.await(task)
    end

    test "never has more than `concurrency` requests in flight" do
      # Arrange
      source = Cite.source(["a", "b", "c", "d", "e", "f"])
      client = held_client(&window_ids/1, client(%{}))
      task = judge_async(client, source, Riddles, window: 1, concurrency: 4)

      # Act + Assert
      [first | others] = arrivals(4)
      refute_receive {:arrive, _, _}
      release([first])
      fifth = arrivals(1)
      refute_receive {:arrive, _, _}
      release(others ++ fifth)
      release(arrivals(1))
      assert %Report{errors: []} = Task.await(task)
    end

    test "sends up to 4 requests at once by default" do
      # Arrange
      source = Cite.source(["a", "b", "c", "d", "e"])
      client = held_client(&window_ids/1, client(%{}))
      task = judge_async(client, source, Riddles, window: 1)

      # Act
      first = arrivals(4)
      refute_receive {:arrive, _, _}
      release(first)
      release(arrivals(1))

      # Assert
      assert %Report{errors: []} = Task.await(task)
    end

    test "keeps round-1 errors and models in window order whatever order replies arrive in" do
      # Arrange
      source = Cite.source(["a", "b", "c", "d"])
      answering = client(%{})

      reply = fn request ->
        case window_ids(request) do
          [id] when id in ["P000", "P002"] ->
            {:error, {:window, id}}

          [id] ->
            {:ok, verdict} = answering.(request)
            {:ok, %{verdict | model: "jev-" <> id}}
        end
      end

      client = held_client(&window_ids/1, reply)
      task = judge_async(client, source, Riddles, window: 1, concurrency: 4)

      # Act
      arrivals(4)
      |> Enum.sort_by(&elem(&1, 0), :desc)
      |> Enum.each(fn {_label, pid} = arrival ->
        ref = Process.monitor(pid)
        release([arrival])
        assert_receive {:DOWN, ^ref, :process, ^pid, _}
      end)

      report = Task.await(task)

      # Assert
      assert report.errors == [
               %Error{concern: nil, passage_ids: ["P000"], reason: {:window, "P000"}},
               %Error{concern: nil, passage_ids: ["P002"], reason: {:window, "P002"}}
             ]

      assert report.models == ["jev-P001", "jev-P003"]
    end

    test "keeps round-2 errors in the policy's concern order whatever order replies arrive in" do
      # Arrange
      source =
        Cite.source([%{id: "U1", text: "I was diagnosed, then we moved.", meta: %{speaker: "B"}}],
          as: "utterances",
          show: [:speaker]
        )

      screening =
        client(%{"U1:client_speaking" => 0.9, "U1:health" => 0.9, "U1:life_event" => 0.9})

      label = fn
        %{"questions" => %{"confirm:U1" => _}} = request ->
          if Jason.encode!(request) =~ "health condition", do: :health, else: :life_event

        _round_1 ->
          nil
      end

      reply = fn
        %{"questions" => %{"confirm:U1" => _}} -> {:error, :held}
        request -> screening.(request)
      end

      task = judge_async(held_client(label, reply), source, TwoConcerns, concurrency: 4)

      # Act
      held = Map.new(arrivals(2))

      for concern <- [:life_event, :health] do
        pid = held[concern]
        ref = Process.monitor(pid)
        send(pid, :go)
        assert_receive {:DOWN, ^ref, :process, ^pid, _}
      end

      report = Task.await(task)

      # Assert
      assert report.errors == [
               %Error{concern: :health, passage_ids: ["U1"], reason: :held},
               %Error{concern: :life_event, passage_ids: ["U1"], reason: :held}
             ]
    end

    test "halves refused windows and screens their siblings at concurrency above 1" do
      # Arrange
      source = Cite.source(["a", "b", "c", "d", "e", "f", "g", "h"])
      client = window_client(&(length(&1) > 2))

      # Act
      report = Cite.judge(client, source, Riddles, window: 4, concurrency: 4)

      # Assert
      assert Enum.sort(windows_sent()) == [
               ["P000", "P001"],
               ["P000", "P001", "P002", "P003"],
               ["P002", "P003"],
               ["P004", "P005"],
               ["P004", "P005", "P006", "P007"],
               ["P006", "P007"]
             ]

      assert {report.errors, map_size(report.screen)} == {[], 8}
    end

    test "re-raises what the client raised, with its stacktrace" do
      # Arrange
      source = Cite.source(["a", "b"])

      # Act
      {error, stacktrace} =
        try do
          Cite.judge(fn _request -> raise "boom" end, source, Riddles,
            window: 1,
            concurrency: 4
          )
        rescue
          error -> {error, __STACKTRACE__}
        end

      # Assert
      assert error == %RuntimeError{message: "boom"}
      assert [{CiteTest, _fun, _arity, _location} | _] = stacktrace
    end

    test "re-throws and re-exits what the client did" do
      judge = &Cite.judge(&1, Cite.source(["a", "b"]), Riddles, window: 1, concurrency: 4)

      assert catch_throw(judge.(fn _request -> throw(:thrown) end)) == :thrown
      assert catch_exit(judge.(fn _request -> exit(:gone) end)) == :gone
    end

    test "raises only once the requests before the raise have answered" do
      # Arrange
      source = Cite.source(["a", "b"])
      answering = client(%{})

      reply = fn request ->
        if window_ids(request) == ["P001"], do: :not_a_verdict, else: answering.(request)
      end

      client = held_client(&window_ids/1, reply)

      task =
        Task.async(fn ->
          catch_error(Cite.judge(client, source, Riddles, window: 1, concurrency: 4))
        end)

      # Act
      held = Map.new(arrivals(2))
      second = held[["P001"]]
      ref = Process.monitor(second)
      send(second, :go)
      assert_receive {:DOWN, ^ref, :process, ^second, _}
      still_running = Task.yield(task, 100)
      send(held[["P000"]], :go)

      # Assert
      assert still_running == nil
      assert %RuntimeError{} = Task.await(task)
    end

    test "starts no request once one has raised" do
      # Arrange / Act
      {task, held} = fail_second_of_four(fn -> :not_a_verdict end, &catch_error(&1.()))

      # Assert
      refute_receive {:arrive, _label, _pid}
      release(held)
      assert %RuntimeError{} = Task.await(task)
    end

    test "stops the requests after a raise that are still in flight" do
      # Arrange
      source = Cite.source(["a", "b", "c"])
      answering = client(%{})

      reply = fn request ->
        if window_ids(request) == ["P001"], do: :not_a_verdict, else: answering.(request)
      end

      client = held_client(&window_ids/1, reply)

      task =
        Task.async(fn ->
          catch_error(Cite.judge(client, source, Riddles, window: 1, concurrency: 4))
        end)

      # Act
      held = Map.new(arrivals(3))
      second = held[["P001"]]
      third = held[["P002"]]
      second_ref = Process.monitor(second)
      send(second, :go)
      assert_receive {:DOWN, ^second_ref, :process, ^second, _}
      send(held[["P000"]], :go)

      # Assert
      assert %RuntimeError{} = Task.await(task)
      # judge/4 raises only once the stream has killed its running tasks and
      # seen them go down. A monitor set on P002 here could land after that
      # and report :noproc.
      refute Process.alive?(third)
    end

    test "exits a caller that traps exits with a linked crash's reason, once the requests before it have answered" do
      # Arrange
      test_pid = self()
      answering = client(%{})

      reply = fn request ->
        if window_ids(request) == ["P001"] do
          send(test_pid, {:crashing, self()})
          spawn_link(fn -> exit(:helper_crashed) end)

          receive do
            :never -> :ok
          end
        else
          answering.(request)
        end
      end

      label = fn request -> if window_ids(request) == ["P000"], do: ["P000"] end
      client = held_client(label, reply)

      task =
        Task.async(fn ->
          Process.flag(:trap_exit, true)

          catch_exit(
            Cite.judge(client, Cite.source(["a", "b"]), Riddles, window: 1, concurrency: 4)
          )
        end)

      # Act
      [{["P000"], first}] = arrivals(1)
      assert_receive {:crashing, second}
      ref = Process.monitor(second)
      assert_receive {:DOWN, ^ref, :process, ^second, _}
      still_running = Task.yield(task, 100)
      send(first, :go)

      # Assert
      assert still_running == nil
      assert Task.await(task) == :helper_crashed
    end

    test "starts no request once a linked crash has killed one, in a caller that traps exits" do
      # Arrange
      crash = fn ->
        spawn_link(fn -> exit(:helper_crashed) end)

        receive do
          :never -> :ok
        end
      end

      trapping = fn judge ->
        Process.flag(:trap_exit, true)
        catch_exit(judge.())
      end

      # Act
      {task, held} = fail_second_of_four(crash, trapping)

      # Assert
      refute_receive {:arrive, _label, _pid}
      release(held)
      assert Task.await(task) == :helper_crashed
    end

    test "leaves a caller that traps exits with an empty mailbox after a run" do
      task =
        Task.async(fn ->
          Process.flag(:trap_exit, true)
          Cite.judge(client(%{}), Cite.source(["a", "b", "c"]), Riddles, window: 1)
          Process.info(self(), :messages)
        end)

      assert Task.await(task) == {:messages, []}
    end

    test "leaves a caller that traps exits with an empty mailbox after a raise" do
      task =
        Task.async(fn ->
          Process.flag(:trap_exit, true)
          catch_error(Cite.judge(fn _request -> :not_a_verdict end, Cite.source(["a"]), Riddles))
          Process.info(self(), :messages)
        end)

      assert Task.await(task) == {:messages, []}
    end

    test "leaves a caller that traps exits with an empty mailbox after a linked crash" do
      task =
        Task.async(fn ->
          Process.flag(:trap_exit, true)

          client = fn _request ->
            spawn_link(fn -> exit(:helper_crashed) end)

            receive do
              :never -> :ok
            end
          end

          catch_exit(Cite.judge(client, Cite.source(["a"]), Riddles))
          Process.info(self(), :messages)
        end)

      assert Task.await(task) == {:messages, []}
    end

    test "stops its requests when the caller dies" do
      # Arrange
      client = held_client(&window_ids/1, client(%{}))
      source = Cite.source(["a", "b"])
      caller = spawn(fn -> Cite.judge(client, source, Riddles, window: 1) end)
      held = arrivals(2)
      refs = Enum.map(held, fn {_label, pid} -> Process.monitor(pid) end)

      # Act
      Process.exit(caller, :kill)

      # Assert
      for ref <- refs, do: assert_receive({:DOWN, ^ref, :process, _pid, _reason})
    end

    test "carries the caller's Logger metadata and process level into the client" do
      test_pid = self()
      answering = client(%{})

      client = fn request ->
        send(
          test_pid,
          {:logger, Logger.metadata()[:request_id], Logger.get_process_level(self())}
        )

        answering.(request)
      end

      # The key is test data, not metadata a log formatter prints.
      # credo:disable-for-next-line Credo.Check.Warning.MissedMetadataKeyInLoggerConfig
      Logger.metadata(request_id: "req-1")
      Logger.put_process_level(self(), :error)
      Cite.judge(client, Cite.source(["a"]), Riddles)

      assert_received {:logger, "req-1", :error}
    end
  end
end
