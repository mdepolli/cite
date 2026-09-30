defmodule Cite.TestHeld do
  @moduledoc false

  # Functions a test holds mid-call, to pace what runs concurrently.

  import ExUnit.Assertions

  # A function that reports each call it holds to the test process as
  # {:arrive, label, pid} and answers only when the test sends pid :go.
  # Calls `label` maps to nil are answered at once.
  @spec held((term() -> term()), (term() -> term())) :: (term() -> term())
  def held(label, answering) do
    test_pid = self()

    fn argument ->
      case label.(argument) do
        nil ->
          answering.(argument)

        held ->
          send(test_pid, {:arrive, held, self()})

          receive do
            :go -> answering.(argument)
          end
      end
    end
  end

  @spec arrivals(non_neg_integer()) :: [{term(), pid()}]
  def arrivals(n) do
    for _ <- 1..n//1 do
      assert_receive {:arrive, label, pid}
      {label, pid}
    end
  end

  @spec release(Enumerable.t({term(), pid()})) :: :ok
  def release(arrivals), do: Enum.each(arrivals, fn {_label, pid} -> send(pid, :go) end)

  # Lets one held call answer and waits for its task to go down, which
  # frees its slot.
  @spec release_and_await(pid()) :: :ok
  def release_and_await(pid) do
    send(pid, :go)
    await_down(pid)
  end

  @spec await_down(pid()) :: :ok
  def await_down(pid) do
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    :ok
  end

  # A function body that links to a helper that crashes, and waits to be
  # killed by it.
  @spec crash_through_link() :: no_return()
  def crash_through_link do
    spawn_link(fn -> exit(:helper_crashed) end)

    receive do
      :never -> :ok
    end
  end
end
