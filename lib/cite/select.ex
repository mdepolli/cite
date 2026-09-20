defmodule Cite.Select do
  @moduledoc """
  The imperative shell behind `Cite.select/5`.

  Chunks candidates into windows, calls the client, halves a window the
  provider refuses as too large, calls the client once per cluster, and
  assembles the `Cite.Result`. Every decision — what to ask, what an answer
  means, what to emit — lives in `Cite.Scan`, `Cite.Compare`, and
  `Cite.Emit`, which never see the client. Internal; use `Cite.select/5`.
  """

  alias Cite.{Candidate, Compare, Emit, Result, Scan}

  @spec select(Cite.client(), String.t(), [Candidate.t()], Cite.spec(), keyword()) :: Result.t()
  def select(client, source, candidates, spec, opts \\ [])
      when is_function(client, 1) and is_binary(source) and is_list(candidates) and is_map(spec) do
    opts =
      Keyword.validate!(opts,
        window_size: 40,
        atomic_threshold: 0.5,
        review_band: {0.4, 0.6},
        confidence_floor: 0.5,
        state: %{}
      )

    window_size = opts[:window_size]
    atomic_threshold = opts[:atomic_threshold]
    review_band = opts[:review_band]
    confidence_floor = opts[:confidence_floor]
    extra_state = opts[:state]
    atomics = spec |> Map.fetch!(:atomics) |> Scan.atomics()
    compose = Map.fetch!(spec, :compose)

    check_options(window_size, atomic_threshold, review_band, confidence_floor, extra_state)
    check_state(extra_state)

    scan =
      candidates
      |> Scan.candidates(source)
      |> Enum.chunk_every(window_size)
      |> Enum.flat_map(&judge_window(client, &1, atomics, extra_state))
      |> Scan.resolve(atomics)

    compare =
      scan.index
      |> Scan.drop_below(atomic_threshold)
      |> compose.(candidates)
      |> Compare.clusters(candidates)
      |> Enum.map(&{&1, judge_cluster(client, &1, extra_state)})
      |> Compare.resolve(review_band)

    %Result{
      spans: Emit.spans(source, compare.accepted, confidence_floor),
      errors: scan.errors ++ compare.errors,
      usage: Result.total_usage(scan.usages ++ compare.usages),
      scan: scan.index,
      rejected: compare.rejected
    }
  end

  defp check_options(window_size, atomic_threshold, {low, high}, confidence_floor, state)
       when is_integer(window_size) and window_size > 0 and is_number(atomic_threshold) and
              is_number(low) and is_number(high) and low < high and
              is_number(confidence_floor) and is_map(state) and not is_struct(state) do
    :ok
  end

  defp check_options(window_size, atomic_threshold, review_band, confidence_floor, state) do
    raise ArgumentError, """
    invalid options: window_size must be a positive integer, atomic_threshold and \
    confidence_floor numbers, review_band {low, high} with low < high, state a map; got \
    #{inspect(window_size: window_size, atomic_threshold: atomic_threshold, review_band: review_band, confidence_floor: confidence_floor, state: state)}
    """
  end

  # The scan puts each window under "candidates"; a caller's entry there would
  # be overwritten without a word.
  defp check_state(state) do
    if Map.has_key?(state, "candidates") or Map.has_key?(state, :candidates) do
      raise ArgumentError, "state must not use the \"candidates\" key; the scan window goes there"
    end
  end

  defp usage(nil), do: :ok

  defp usage(%{input_tokens: input, output_tokens: output})
       when is_integer(input) and input >= 0 and is_integer(output) and output >= 0,
       do: :ok

  defp usage(other) do
    raise ArgumentError,
          "client usage must be nil or %{input_tokens: n, output_tokens: n}, got: #{inspect(other)}"
  end

  # A window over the request token cap is split in half and both halves
  # judged; only a single candidate that still exceeds it is an error.
  defp judge_window(client, window, atomics, extra_state) do
    case call(client, Scan.request(window, atomics, extra_state)) do
      {:error, :request_too_large} when length(window) > 1 ->
        {left, right} = Enum.split(window, div(length(window), 2))

        judge_window(client, left, atomics, extra_state) ++
          judge_window(client, right, atomics, extra_state)

      verdict ->
        [{window, verdict}]
    end
  end

  defp judge_cluster(client, cluster, extra_state) do
    case Compare.request(cluster, extra_state) do
      nil -> :unasked
      request -> call(client, request)
    end
  end

  # The client is the caller's function; its return is checked here, once, and
  # trusted everywhere after.
  defp call(client, request) do
    case client.(request) do
      {:ok, %{answers: answers, usage: usage}} = verdict when is_map(answers) ->
        usage(usage)
        verdict

      {:error, _reason} = error ->
        error

      other ->
        raise ArgumentError, """
        client must return {:ok, %{answers: map, usage: map | nil}} or {:error, reason}, \
        got: #{inspect(other)}
        """
    end
  end
end
