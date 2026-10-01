defmodule Cite.RoundTest do
  use ExUnit.Case, async: true

  import Cite.TestHeld

  alias Cite.Round

  # Runs the items in a task, each held until the test releases it, so the
  # test process is free to pace them.
  defp run_held(items, concurrency) do
    fun = held(& &1, & &1)
    Task.async(fn -> Round.run(items, concurrency, fun) end)
  end

  # Runs `items`, counted from 0, at concurrency 4 with every item held.
  # Item 1 calls `failing` in place of an answer; `catching` runs the round
  # in the caller task and returns what it failed with. Releases item 1
  # alone and waits for its task to go down. Returns the caller task and the
  # items still held.
  defp fail_item_1(items, failing, catching) do
    fun = held(& &1, fn item -> if item == 1, do: failing.(), else: item end)
    task = Task.async(fn -> catching.(fn -> Round.run(items, 4, fun) end) end)

    {failed, others} =
      items
      |> length()
      |> min(4)
      |> arrivals()
      |> Map.new()
      |> Map.pop(1)

    release_and_await(failed)

    {task, others}
  end

  defp trap_and_catch_exit(round) do
    Process.flag(:trap_exit, true)
    catch_exit(round.())
  end

  describe "run/3" do
    test "returns the results in item order, whatever order the items finish in" do
      task = run_held([:a, :b, :c], 3)

      arrivals(3)
      |> Enum.sort_by(&elem(&1, 0), :desc)
      |> Enum.each(fn {_item, pid} -> release_and_await(pid) end)

      assert Task.await(task) == [:a, :b, :c]
    end

    test "never runs more than `concurrency` items at once" do
      # Arrange
      task = run_held([1, 2, 3, 4, 5, 6], 4)

      # Act + Assert
      [first | others] = arrivals(4)
      refute_receive {:arrive, _, _}
      release([first])
      fifth = arrivals(1)
      refute_receive {:arrive, _, _}
      release(others ++ fifth)
      release(arrivals(1))
      assert Task.await(task) == [1, 2, 3, 4, 5, 6]
    end

    test "stops its items when the caller dies" do
      # Arrange
      fun = held(& &1, & &1)
      caller = spawn(fn -> Round.run([1, 2], 4, fun) end)
      refs = for {_item, pid} <- arrivals(2), do: Process.monitor(pid)

      # Act
      Process.exit(caller, :kill)

      # Assert
      for ref <- refs, do: assert_receive({:DOWN, ^ref, :process, _pid, _reason})
    end

    test "carries the caller's Logger metadata and process level into each item" do
      test_pid = self()

      fun = fn _item ->
        send(
          test_pid,
          {:logger, Logger.metadata()[:request_id], Logger.get_process_level(self())}
        )
      end

      # The key is test data, not metadata a log formatter prints.
      # credo:disable-for-next-line Credo.Check.Warning.MissedMetadataKeyInLoggerConfig
      Logger.metadata(request_id: "req-1")
      Logger.put_process_level(self(), :error)
      Round.run([1], 4, fun)

      assert_received {:logger, "req-1", :error}
    end
  end

  describe "run/3 when an item fails" do
    test "re-raises what the function raised, with its stacktrace" do
      # Act
      {error, stacktrace} =
        try do
          Round.run([1, 2], 4, fn _item -> raise "boom" end)
        rescue
          error -> {error, __STACKTRACE__}
        end

      # Assert
      assert error == %RuntimeError{message: "boom"}
      assert [{Cite.RoundTest, _fun, _arity, _location} | _] = stacktrace
    end

    test "re-throws and re-exits what the function did" do
      assert catch_throw(Round.run([1, 2], 4, fn _item -> throw(:thrown) end)) == :thrown
      assert catch_exit(Round.run([1, 2], 4, fn _item -> exit(:gone) end)) == :gone
    end

    test "raises the first failure in item order, not the first to arrive" do
      # Arrange
      test_pid = self()

      fun = fn
        0 ->
          send(test_pid, {:held, self()})

          receive do
            :go -> raise "first"
          end

        1 ->
          send(test_pid, {:failing, self()})
          raise "second"
      end

      task = Task.async(fn -> catch_error(Round.run([0, 1], 2, fun)) end)

      # Act
      assert_receive {:held, first}
      assert_receive {:failing, second}
      await_down(second)
      send(first, :go)

      # Assert
      assert Task.await(task) == %RuntimeError{message: "first"}
    end

    test "starts no item once a failure waits in the mailbox, even with a slot free" do
      # Arrange
      test_pid = self()

      # Item 1 is pulled only once item 0's task is down, so its failure is
      # already in the mailbox when item 1 would start.
      items =
        Stream.map([0, 1, 2], fn
          1 ->
            assert_receive {:failing, pid}
            await_down(pid)
            1

          item ->
            item
        end)

      fun = fn
        0 ->
          send(test_pid, {:failing, self()})
          raise "no first item"

        item ->
          send(test_pid, {:ran, item})
      end

      # Act
      assert_raise RuntimeError, "no first item", fn -> Round.run(items, 4, fun) end

      # Assert
      assert Process.info(self(), :messages) == {:messages, []}
    end

    test "stops the items after a failure at once, while the items before it still run" do
      # Arrange / Act
      {task, held} = fail_item_1([0, 1, 2], fn -> raise "boom" end, &catch_error(&1.()))

      # Assert
      await_down(held[2])
      send(held[0], :go)
      assert Task.await(task) == %RuntimeError{message: "boom"}
    end
  end

  describe "run/3 in a caller that traps exits" do
    test "exits with a linked crash's reason, once the items before it have answered" do
      # Arrange / Act
      {task, held} = fail_item_1([0, 1], &crash_through_link/0, &trap_and_catch_exit/1)
      still_running = Task.yield(task, 100)
      release(held)

      # Assert
      assert still_running == nil
      assert Task.await(task) == :helper_crashed
    end

    test "starts no item once a linked crash has killed one" do
      # Arrange / Act
      {task, held} =
        fail_item_1([0, 1, 2, 3, 4, 5, 6, 7], &crash_through_link/0, &trap_and_catch_exit/1)

      # Assert
      refute_receive {:arrive, _item, _pid}
      release(held)
      assert Task.await(task) == :helper_crashed
    end

    test "leaves the mailbox empty after a round" do
      Process.flag(:trap_exit, true)
      Round.run([1, 2, 3], 4, & &1)

      assert Process.info(self(), :messages) == {:messages, []}
    end

    test "leaves the mailbox empty after a raise" do
      Process.flag(:trap_exit, true)
      catch_error(Round.run([1], 4, fn _item -> raise "boom" end))

      assert Process.info(self(), :messages) == {:messages, []}
    end

    test "leaves the mailbox empty after a linked crash" do
      Process.flag(:trap_exit, true)
      catch_exit(Round.run([1], 4, fn _item -> crash_through_link() end))

      assert Process.info(self(), :messages) == {:messages, []}
    end
  end
end
