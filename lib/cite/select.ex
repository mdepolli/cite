defmodule Cite.Select do
  # The imperative shell: chunks, calls the judge, retries on overflow, and
  # hands every decision to Scan, Compare, and Emit. Entry point is Cite.select/5.
  @moduledoc false

  alias Cite.{Candidate, Compare, Emit, Result, Scan}

  @spec select(Cite.judge(), String.t(), [Candidate.t()], Cite.spec(), keyword()) :: Result.t()
  def select(judge, source, candidates, spec, opts \\ [])
      when is_function(judge, 1) and is_binary(source) and is_list(candidates) and is_map(spec) do
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
    atomics = Map.fetch!(spec, :atomics)
    compose = Map.fetch!(spec, :compose)

    check_options(window_size, atomic_threshold, review_band, confidence_floor, extra_state)

    scan =
      candidates
      |> Scan.candidates(source)
      |> Enum.chunk_every(window_size)
      |> Enum.flat_map(&judge_window(judge, &1, atomics, extra_state))
      |> Scan.resolve(atomics)

    compare =
      scan.index
      |> Scan.drop_below(atomic_threshold)
      |> compose.(candidates)
      |> Compare.clusters(candidates)
      |> Enum.map(&{&1, judge_cluster(judge, &1, extra_state)})
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
              is_number(low) and is_number(high) and low <= high and
              is_number(confidence_floor) and is_map(state) do
    :ok
  end

  defp check_options(window_size, atomic_threshold, review_band, confidence_floor, state) do
    raise ArgumentError,
          "invalid options: window_size must be a positive integer, atomic_threshold and " <>
            "confidence_floor numbers, review_band {low, high} with low <= high, state a map; " <>
            "got #{inspect(window_size: window_size, atomic_threshold: atomic_threshold, review_band: review_band, confidence_floor: confidence_floor, state: state)}"
  end

  # A window over the request token cap is split in half and both halves
  # judged; only a single candidate that still exceeds it is an error.
  defp judge_window(judge, window, atomics, extra_state) do
    case judge.(Scan.request(window, atomics, extra_state)) do
      {:error, :request_too_large} when length(window) > 1 ->
        {left, right} = Enum.split(window, div(length(window), 2))

        judge_window(judge, left, atomics, extra_state) ++
          judge_window(judge, right, atomics, extra_state)

      verdict ->
        [{window, verdict}]
    end
  end

  defp judge_cluster(judge, cluster, extra_state) do
    case Compare.request(cluster, extra_state) do
      nil -> :unasked
      request -> judge.(request)
    end
  end
end
