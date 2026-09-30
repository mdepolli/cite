defmodule Cite.Round do
  @moduledoc """
  Sends one round's requests: runs a function on each item, up to
  `concurrency` at once, and returns the results in item order.

  Each item runs in a task linked to the caller, so the caller's death
  stops its requests. Once one fails, by a raise, throw, or exit, or by an
  exit signal from outside, no further item starts. The failure reaches
  the caller once the items before it have answered, and the items after
  it still running are killed. Of several failures, the first in item
  order wins.

  The caller's mailbox is left as it was, even when it traps exits.
  """

  # Nothing in the caller may raise between the first task and
  # stop_the_rest/1: there is no try/after to kill the tasks on the way out.
  # A new step in the loop, such as a deadline, must keep it so or add one.
  @spec run(Enumerable.t(), pos_integer(), (term() -> term())) :: [term()]
  def run(items, concurrency, fun) do
    logger = {Logger.metadata(), Logger.get_process_level(self())}
    start = fn item -> Task.async(fn -> attempt(fun, item, logger) end) end

    items
    |> Stream.with_index()
    |> Enum.reduce_while(%{running: %{}, outcomes: %{}, failed_at: nil}, fn item, state ->
      start_next(item, state, concurrency, start)
    end)
    |> await_before_failure()
    |> stop_the_rest()
    |> results()
  end

  # A task starts with an empty process dictionary; the caller's Logger
  # state goes with it, so the client logs as the caller would.
  defp attempt(fun, item, {metadata, level}) do
    Logger.metadata(metadata)
    put_process_level(level)
    {:ok, fun.(item)}
  catch
    kind, reason -> {:raised, kind, reason, __STACKTRACE__}
  end

  defp put_process_level(nil), do: :ok
  defp put_process_level(level), do: Logger.put_process_level(self(), level)

  # A slot can be free while a failure sits unread in the mailbox, so every
  # reply already in is read before the item starts.
  defp start_next({item, index}, state, concurrency, start) do
    state
    |> collect_ready()
    |> start_unless_failed(item, index, concurrency, start)
  end

  defp start_unless_failed(%{failed_at: nil} = state, item, index, concurrency, start) do
    task = start.(item)

    state
    |> put_in([:running, task.ref], {index, task})
    |> fill_slot(concurrency)
  end

  defp start_unless_failed(state, _item, _index, _concurrency, _start), do: {:halt, state}

  defp fill_slot(%{running: running} = state, concurrency) when map_size(running) < concurrency,
    do: {:cont, state}

  defp fill_slot(state, _concurrency), do: {:cont, await_one(state)}

  defp collect_ready(state) do
    case receive_one(state, 0) do
      {:ok, state} -> collect_ready(state)
      :timeout -> state
    end
  end

  defp await_one(state) do
    {:ok, state} = receive_one(state, :infinity)
    state
  end

  # A :DOWN with no reply first is a task killed from outside, by a crash
  # in a process the client linked to or any other exit signal.
  defp receive_one(%{running: running} = state, timeout) do
    receive do
      {ref, reply} when is_map_key(running, ref) ->
        {:ok, finish(state, ref, reply)}

      {:DOWN, ref, :process, _pid, reason} when is_map_key(running, ref) ->
        {:ok, finish(state, ref, {:exit, reason})}
    after
      timeout -> :timeout
    end
  end

  # A linked task that exits sends a caller that traps exits an :EXIT, even
  # on a normal exit. Once unlink/1 returns no more can come, but one may
  # already be queued.
  defp finish(state, ref, outcome) do
    {{index, task}, running} = Map.pop!(state.running, ref)
    Process.demonitor(ref, [:flush])
    Process.unlink(task.pid)
    drop_exit(task.pid)

    %{
      state
      | running: running,
        outcomes: Map.put(state.outcomes, index, outcome),
        failed_at: first_failure(state.failed_at, index, outcome)
    }
  end

  defp first_failure(failed_at, _index, {:ok, _value}), do: failed_at
  defp first_failure(nil, index, _failure), do: index
  defp first_failure(failed_at, index, _failure), do: min(failed_at, index)

  defp await_before_failure(state) do
    if Enum.any?(state.running, fn {_ref, {index, _task}} -> before?(index, state.failed_at) end) do
      state
      |> await_one()
      |> await_before_failure()
    else
      state
    end
  end

  defp before?(_index, nil), do: true
  defp before?(index, failed_at), do: index < failed_at

  # Task.shutdown/2 unlinks before it kills, but an :EXIT from a task that
  # already died, killed from outside, may be queued. What it returns is not
  # needed: every task still running comes after the failure.
  defp stop_the_rest(state) do
    for {_ref, {_index, task}} <- state.running do
      Task.shutdown(task, :brutal_kill)
      drop_exit(task.pid)
    end

    %{state | running: %{}}
  end

  defp drop_exit(pid) do
    receive do
      {:EXIT, ^pid, _reason} -> :ok
    after
      0 -> :ok
    end
  end

  defp results(%{failed_at: nil, outcomes: outcomes}) do
    outcomes
    |> Enum.sort_by(fn {index, _outcome} -> index end)
    |> Enum.map(fn {_index, {:ok, value}} -> value end)
  end

  defp results(%{failed_at: index, outcomes: outcomes}), do: fail(Map.fetch!(outcomes, index))

  defp fail({:raised, kind, reason, stacktrace}), do: :erlang.raise(kind, reason, stacktrace)
  defp fail({:exit, reason}), do: exit(reason)
end
