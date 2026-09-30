defmodule Cite.RoundTest do
  use ExUnit.Case, async: true

  alias Cite.Round

  describe "run/3" do
    test "kills the tasks it started when the items raise, and leaves the mailbox empty" do
      # Arrange
      test_pid = self()

      # The second item raises only once the first one's task is running.
      items =
        Stream.map(1..3, fn
          2 ->
            assert_receive {:started, 1, first}
            send(test_pid, {:first, first})
            raise "no second item"

          item ->
            item
        end)

      held = fn item ->
        send(test_pid, {:started, item, self()})

        receive do
          :never -> item
        end
      end

      # Act
      assert_raise RuntimeError, "no second item", fn -> Round.run(items, 4, held) end

      # Assert
      assert_received {:first, first}
      refute Process.alive?(first)
      assert Process.info(self(), :messages) == {:messages, []}
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
      ref = Process.monitor(second)
      assert_receive {:DOWN, ^ref, :process, ^second, _reason}
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
            ref = Process.monitor(pid)
            assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
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
  end
end
