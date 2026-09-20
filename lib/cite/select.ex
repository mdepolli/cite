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

  alias Cite.Answer
  alias Cite.Candidate
  alias Cite.Cluster
  alias Cite.Error
  alias Cite.Question
  alias Cite.Result
  alias Cite.Span
  alias Cite.Wire

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

    {index, scan_errors, scan_usages} =
      scan(judge, candidates, atomics, extra_state, window_size)

    filtered = drop_below(index, atomic_threshold)
    clusters = compose.(filtered, candidates)
    ensure_known_members(clusters, candidates)

    compare = compare(judge, clusters, extra_state, review_band)

    %Result{
      spans: emit(source, compare.accepted, confidence_floor),
      errors: scan_errors ++ compare.errors,
      usage: total_usage(scan_usages ++ compare.usages),
      scan: index,
      rejected: compare.rejected
    }
  end

  defp scan(judge, candidates, atomics, extra_state, window_size) do
    outcomes =
      candidates
      |> Enum.chunk_every(window_size)
      |> Enum.flat_map(&judge_window(judge, &1, atomics, extra_state))

    index = Enum.reduce(outcomes, %{}, &merge_scores(&1, &2, atomics))
    errors = for {window, {:error, reason}} <- outcomes, do: range_error(window, reason)
    usages = for {_window, {:ok, verdict}} <- outcomes, do: verdict.usage

    {index, errors, usages}
  end

  # A window over the request token cap is split in half and both halves
  # judged; only a single candidate that still exceeds it is an error.
  defp judge_window(judge, window, atomics, extra_state) do
    case judge.(scan_request(window, atomics, extra_state)) do
      {:error, {:bad_request, "max_tokens_exceeded"}} when length(window) > 1 ->
        {left, right} = Enum.split(window, div(length(window), 2))

        judge_window(judge, left, atomics, extra_state) ++
          judge_window(judge, right, atomics, extra_state)

      verdict ->
        [{window, verdict}]
    end
  end

  defp scan_request(window, atomics, extra_state) do
    questions =
      for %Candidate{} = candidate <- window, atomic <- atomics, into: %{} do
        {scan_key(candidate.id, atomic.name), Question.encode(atomic.question.(candidate))}
      end

    state =
      extra_state
      |> Wire.map()
      |> Map.put("candidates", Map.new(window, &{&1.id, Wire.candidate(&1)}))

    %{"state" => state, "questions" => questions}
  end

  defp merge_scores({_window, {:error, _reason}}, index, _atomics), do: index

  defp merge_scores({window, {:ok, %{answers: answers}}}, index, atomics) do
    Enum.reduce(window, index, fn %Candidate{id: id}, acc ->
      scores = Map.new(atomics, &{&1.name, Answer.noul(answers[scan_key(id, &1.name)])})
      Map.update(acc, id, scores, &Map.merge(&1, scores))
    end)
  end

  defp range_error(candidates, reason) do
    starts = Enum.map(candidates, & &1.byte_start)
    stops = Enum.map(candidates, & &1.byte_end)
    Error.from_range(Enum.min(starts), Enum.max(stops), reason)
  end

  defp drop_below(index, threshold) do
    Map.new(index, fn {id, scores} ->
      kept = for {name, value} <- scores, value > threshold, into: %{}, do: {name, value}
      {id, kept}
    end)
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

  defp compare(judge, clusters, extra_state, review_band) do
    outcomes = Enum.map(clusters, &{&1, judge_cluster(judge, &1, extra_state)})

    decisions =
      for {cluster, {:ok, %{answers: answers}}} <- outcomes do
        {cluster, answers, decide(cluster, answers, review_band)}
      end

    accepted =
      for {cluster, answers, {decision, members}} <- decisions, decision != :reject do
        {cluster, members, answers, decision == :review}
      end

    rejected =
      for {cluster, answers, {:reject, _members}} <- decisions, into: %{} do
        {cluster.id, %{"members" => Enum.map(cluster.members, & &1.id), "answers" => answers}}
      end

    errors = for {cluster, {:error, reason}} <- outcomes, do: range_error(cluster.members, reason)
    usages = for {_cluster, {:ok, verdict}} <- outcomes, do: verdict.usage

    %{accepted: accepted, rejected: rejected, errors: errors, usages: usages}
  end

  # No questions means nothing to ask: the cluster is accepted without a call.
  defp judge_cluster(_judge, %Cluster{questions: questions}, _state) when questions == %{} do
    {:ok, %{answers: %{}, usage: nil}}
  end

  defp judge_cluster(judge, %Cluster{} = cluster, extra_state) do
    judge.(compare_request(cluster, extra_state))
  end

  defp compare_request(%Cluster{state: state, questions: questions}, extra_state) do
    %{
      "state" => Map.merge(Wire.map(extra_state), Wire.map(state)),
      "questions" => Wire.questions(questions)
    }
  end

  # A cluster that clears the gate but grounds no member has nothing to cite,
  # so it is rejected rather than vanishing from the result.
  defp decide(cluster, answers, {low, _high} = band) do
    case {gate(cluster, answers, band), evidencing_members(cluster, answers, low)} do
      {:reject, members} -> {:reject, members}
      {_decision, []} -> {:reject, []}
      {decision, members} -> {decision, members}
    end
  end

  # Gate over every :noul question key. Missing/malformed answers read as 0.0
  # (same as scan) so unanswered Nouls cannot silently drop out of :all.
  # No Noul questions → accept (Score/Choice-only clusters have nothing to gate).
  defp gate(%Cluster{match: match, questions: questions}, answers, band) do
    values =
      for {key, %Question{type: :noul}} <- questions do
        Answer.noul(answers[key])
      end

    gate_values(match, values, band)
  end

  defp gate_values(_match, [], _band), do: :accept

  defp gate_values(:any, values, {low, high}) do
    cond do
      Enum.any?(values, &(&1 >= high)) -> :accept
      Enum.any?(values, &(&1 > low)) -> :review
      true -> :reject
    end
  end

  defp gate_values(:all, values, {low, high}) do
    cond do
      Enum.any?(values, &(&1 <= low)) -> :reject
      Enum.all?(values, &(&1 >= high)) -> :accept
      true -> :review
    end
  end

  defp emit(_source, [], _floor), do: []

  defp emit(source, accepted, confidence_floor) do
    Enum.flat_map(accepted, fn {cluster, members, answers, review?} ->
      spans = Span.from_candidates(source, members)
      attributes = emit_attributes(cluster, answers, review?, confidence_floor)

      Enum.map(spans, fn %Span{} = span ->
        %Span{span | class: cluster.class, attributes: attributes}
      end)
    end)
  end

  # A cluster may name the questions that verify a member; such a member is
  # grounded only when one of its Nouls clears the reject edge. Members it
  # does not name are always evidence.
  defp evidencing_members(%Cluster{member_questions: keys_by_id} = cluster, answers, low) do
    Enum.filter(cluster.members, fn %Candidate{id: id} ->
      grounded?(Map.get(keys_by_id, id), answers, low)
    end)
  end

  defp grounded?(nil, _answers, _low), do: true
  defp grounded?(keys, answers, low), do: Enum.any?(keys, &(Answer.noul(answers[&1]) > low))

  defp emit_attributes(%Cluster{questions: questions} = cluster, answers, review?, floor) do
    labels =
      Enum.reduce(questions, %{}, fn {key, question}, acc ->
        case Answer.label(question, answers[key], floor) do
          nil -> acc
          value -> Map.put(acc, key, value)
        end
      end)

    Map.merge(labels, %{
      "cluster_id" => cluster.id,
      "compare" => answers,
      "review" => review?
    })
  end

  defp scan_key(id, atomic_name), do: id <> ":" <> to_string(atomic_name)

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
