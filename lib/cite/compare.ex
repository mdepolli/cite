defmodule Cite.Compare do
  # The compare round, minus the judge call: a cluster becomes a request, and
  # the judged outcomes become accepted/rejected buckets. Pure.
  @moduledoc false

  alias Cite.{Answer, Candidate, Cluster, Error, Question, Wire}

  @type band :: {number(), number()}
  @type outcome :: {Cluster.t(), {:ok, map()} | {:error, term()} | :unasked}
  @type accepted :: %{
          cluster: Cluster.t(),
          members: [Candidate.t()],
          answers: map(),
          review?: boolean()
        }

  @doc """
  Checks what `compose` returned: a list of `%Cluster{}` with unique ids whose
  members are all among `candidates`. Raises `ArgumentError` otherwise.
  """
  @spec clusters(term(), [Candidate.t()]) :: [Cluster.t()]
  def clusters(clusters, candidates) when is_list(clusters) do
    known = MapSet.new(candidates, & &1.id)
    Enum.each(clusters, &cluster_members(&1, known))

    ids = Enum.map(clusters, fn %Cluster{id: id} -> id end)

    if length(ids) != MapSet.size(MapSet.new(ids)) do
      raise ArgumentError, "compose returned duplicate cluster ids: #{inspect(ids)}"
    end

    clusters
  end

  def clusters(other, _candidates) do
    raise ArgumentError, "compose must return a list of clusters, got: #{inspect(other)}"
  end

  @doc """
  One compare request: the cluster's questions over `extra_state` overlaid
  with the cluster's own state. `nil` when the cluster has no questions —
  there is nothing to ask, and the shell records the outcome as `:unasked`.
  """
  @spec request(Cluster.t(), map()) :: map() | nil
  def request(%Cluster{questions: questions}, _extra_state) when questions == %{}, do: nil

  def request(%Cluster{state: state, questions: questions}, extra_state) do
    %{
      "state" => Map.merge(Wire.map(extra_state), Wire.map(state)),
      "questions" => Wire.questions(questions)
    }
  end

  @doc """
  Sorts judged clusters into `accepted` (with their grounded members and a
  review flag), `rejected` (keyed by cluster id, with members and answers),
  one error per failed call, and the usage of each successful one.
  """
  @spec resolve([outcome()], band()) :: %{
          accepted: [accepted()],
          rejected: %{String.t() => map()},
          errors: [Error.t()],
          usages: [Cite.usage() | nil]
        }
  def resolve(outcomes, band) do
    decisions =
      for {cluster, verdict} <- outcomes, answers = answers(verdict), is_map(answers) do
        {cluster, answers, decide(cluster, answers, band)}
      end

    %{
      accepted:
        for {cluster, answers, {decision, members}} <- decisions, decision != :reject do
          %{cluster: cluster, members: members, answers: answers, review?: decision == :review}
        end,
      rejected:
        for {cluster, answers, {:reject, _members}} <- decisions, into: %{} do
          {cluster.id, %{"members" => Enum.map(cluster.members, & &1.id), "answers" => answers}}
        end,
      errors:
        for {cluster, {:error, reason}} <- outcomes do
          Error.from_candidates(cluster.members, reason)
        end,
      usages: for({_cluster, {:ok, verdict}} <- outcomes, do: verdict.usage)
    }
  end

  # The gate decision and the members it grounds. A cluster that clears the
  # gate but grounds no member has nothing to cite, so it is rejected rather
  # than vanishing from the result.
  defp decide(cluster, answers, {low, _high} = band) do
    case {gate(cluster, answers, band), evidencing_members(cluster, answers, low)} do
      {:reject, members} -> {:reject, members}
      {_decision, []} -> {:reject, []}
      {decision, members} -> {decision, members}
    end
  end

  # An unasked cluster answers nothing, which the gate accepts (no Nouls) and
  # evidence grounds fully (no member_questions can name a question).
  defp answers(:unasked), do: %{}
  defp answers({:ok, %{answers: answers}}) when is_map(answers), do: answers
  defp answers({:error, _reason}), do: nil

  defp answers({:ok, other}) do
    raise ArgumentError, "judge verdict must carry :answers, got: #{inspect(other)}"
  end

  defp cluster_members(%Cluster{id: cluster_id, members: members}, known) do
    Enum.each(members, &member(&1, cluster_id, known))
  end

  defp cluster_members(other, _known) do
    raise ArgumentError, "compose must return Cluster structs, got: #{inspect(other)}"
  end

  defp member(%Candidate{id: id}, cluster_id, known) do
    unless MapSet.member?(known, id) do
      raise ArgumentError,
            "cluster #{inspect(cluster_id)} member #{inspect(id)} is not in candidates"
    end
  end

  defp member(other, cluster_id, _known) do
    raise ArgumentError,
          "cluster #{inspect(cluster_id)} members must be Candidate structs, got: #{inspect(other)}"
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
end
