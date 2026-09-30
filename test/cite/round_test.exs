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
  end
end
