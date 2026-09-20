defmodule Cite.Select do
  @moduledoc """
  Atomic scan over candidates, compose clusters in code, compare on a tiny state.

  `judge` is a 1-arity function:
  `request -> {:ok, verdict} | {:error, reason}` where `verdict` is
  `%{answers: map(), usage: %{input_tokens: non_neg_integer(), output_tokens: non_neg_integer()} | nil}`.
  Request maps are wire-shaped (string keys); `Cite.Question.encode/1` runs at
  this edge.

  `spec.atomics` is a list of `%{name: String.t(), question: (Candidate.t() -> Question.t())}`.
  Scan keys are `"\#{candidate.id}:\#{atomic.name}"`.

  `spec.compose` is `index, candidates -> [Cluster.t()]`. `index` is
  `%{candidate_id => %{atomic_name => noul}}` after `atomic_threshold`.

  Scan state puts each window under `"candidates"` as
  `%{id => meta_with_text}` — candidate `meta` passes through (atom keys
  stringified for the wire), with `"text"` set from the candidate.

  Compare attributes are typed from `cluster.questions`: each `:score` emits
  `round(score)` under its key, each `:choice` emits `choice`; both become
  `"uncertain"` when confidence is below `confidence_floor`. Cite does not
  know question names — Vuln maps score integers to domain labels.
  """

  alias Cite.{Candidate, Cluster, Compare, Emit, Question, Result, Scan}

  @type usage :: %{input_tokens: non_neg_integer(), output_tokens: non_neg_integer()}
  @type verdict :: %{answers: map(), usage: usage() | nil}
  @type judge :: (map() -> {:ok, verdict()} | {:error, term()})
  @type atomic :: %{name: String.t(), question: (Candidate.t() -> Question.t())}
  @type spec :: %{atomics: [atomic()], compose: (map(), [Candidate.t()] -> [Cluster.t()])}

  @spec select(judge(), String.t(), [Candidate.t()], spec(), keyword()) :: Result.t()
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

    ensure_unique_candidate_ids(candidates)

    scan =
      candidates
      |> Enum.chunk_every(window_size)
      |> Enum.flat_map(&judge_window(judge, &1, atomics, extra_state))
      |> Scan.resolve(atomics)

    clusters =
      scan.index
      |> Scan.drop_below(atomic_threshold)
      |> compose.(candidates)
      |> ensure_known_members(candidates)

    compare =
      clusters
      |> Enum.map(&{&1, judge_cluster(judge, &1, extra_state)})
      |> Compare.resolve(review_band)

    %Result{
      spans: Emit.spans(source, compare.accepted, confidence_floor),
      errors: scan.errors ++ compare.errors,
      usage: total_usage(scan.usages ++ compare.usages),
      scan: scan.index,
      rejected: compare.rejected
    }
  end

  # A window over the request token cap is split in half and both halves
  # judged; only a single candidate that still exceeds it is an error.
  defp judge_window(judge, window, atomics, extra_state) do
    case judge.(Scan.request(window, atomics, extra_state)) do
      {:error, {:bad_request, "max_tokens_exceeded"}} when length(window) > 1 ->
        {left, right} = Enum.split(window, div(length(window), 2))

        judge_window(judge, left, atomics, extra_state) ++
          judge_window(judge, right, atomics, extra_state)

      verdict ->
        [{window, verdict}]
    end
  end

  # No questions means nothing to ask: the cluster is accepted without a call.
  defp judge_cluster(_judge, %Cluster{questions: questions}, _state) when questions == %{} do
    {:ok, %{answers: %{}, usage: nil}}
  end

  defp judge_cluster(judge, %Cluster{} = cluster, extra_state) do
    judge.(Compare.request(cluster, extra_state))
  end

  defp ensure_known_members(clusters, candidates) when is_list(clusters) do
    known = MapSet.new(candidates, & &1.id)
    Enum.each(clusters, &ensure_cluster_members(&1, known))
    ensure_unique_cluster_ids(clusters)
    clusters
  end

  defp ensure_known_members(other, _candidates) do
    raise ArgumentError, "compose must return a list of clusters, got: #{inspect(other)}"
  end

  defp ensure_cluster_members(%Cluster{id: cluster_id, members: members}, known) do
    Enum.each(members, &ensure_member(&1, cluster_id, known))
  end

  defp ensure_cluster_members(other, _known) do
    raise ArgumentError, "compose must return Cluster structs, got: #{inspect(other)}"
  end

  defp ensure_member(%Candidate{id: id}, cluster_id, known) do
    unless MapSet.member?(known, id) do
      raise ArgumentError,
            "cluster #{inspect(cluster_id)} member #{inspect(id)} is not in candidates"
    end
  end

  defp ensure_member(other, cluster_id, _known) do
    raise ArgumentError,
          "cluster #{inspect(cluster_id)} members must be Candidate structs, got: #{inspect(other)}"
  end

  defp ensure_unique_candidate_ids(candidates) do
    dupes = for {id, n} <- Enum.frequencies_by(candidates, & &1.id), n > 1, do: id

    if dupes != [] do
      raise ArgumentError,
            "candidate ids must be unique, duplicated: #{inspect(Enum.sort(dupes))}"
    end
  end

  defp ensure_unique_cluster_ids(clusters) do
    ids = Enum.map(clusters, fn %Cluster{id: id} -> id end)

    if length(ids) != MapSet.size(MapSet.new(ids)) do
      raise ArgumentError, "compose returned duplicate cluster ids: #{inspect(ids)}"
    end
  end

  defp total_usage(usages) do
    present = Enum.reject(usages, &is_nil/1)

    case present do
      [] ->
        nil

      _ ->
        %{
          input_tokens: Enum.sum(Enum.map(present, & &1.input_tokens)),
          output_tokens: Enum.sum(Enum.map(present, & &1.output_tokens))
        }
    end
  end
end
