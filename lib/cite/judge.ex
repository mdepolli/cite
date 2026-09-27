defmodule Cite.Judge do
  @moduledoc """
  Round 2, minus the client call: a gathered finding becomes one request on
  its own evidence, and the reply becomes a `Cite.Finding` under the verdict
  rules. Pure. Internal.
  """

  alias Cite.{Answer, Citation, Error, Finding, Gathered, Passage, Run, Source, Wire}
  alias Cite.Policy.{Check, Concern, Role, Terms}

  @type outcome :: {Gathered.t(), {:ok, Cite.verdict()} | {:error, term()}}

  @doc """
  The round-2 request. A directly screened concern: its passages under the
  source's `as`, a confirm per passage keyed `"confirm:<id>"`, the
  descriptors over all of them. A concern built from factors: each role at
  the top level, the checks that apply, the descriptors over every role.
  """
  @spec request(Run.t(), Gathered.t()) :: map()
  def request(
        %Run{source: %Source{show: show}} = run,
        %Gathered{concern: %Concern{detect: nil}} = gathered
      ) do
    state =
      Map.new(gathered.roles, fn {role, passage} ->
        {Atom.to_string(role), Wire.passage(passage, show)}
      end)

    paths =
      Map.new(gathered.roles, fn {role, _passage} ->
        {Atom.to_string(role), Wire.text_path(role)}
      end)

    fallback =
      for %Role{name: role} <- gathered.concern.roles,
          Map.has_key?(gathered.roles, role),
          do: Wire.text_path(role)

    checks =
      for %Check{} = check <- asked(gathered), into: %{} do
        {Atom.to_string(check.name), Wire.question(check.question, paths, [])}
      end

    %{
      "state" => state,
      "questions" => Map.merge(checks, descriptor_questions(run.terms, fallback))
    }
  end

  def request(
        %Run{source: %Source{as: as, show: show}} = run,
        %Gathered{concern: %Concern{confirm: confirm}, passages: passages}
      ) do
    confirms =
      for %Passage{id: id} <- passages, into: %{} do
        {confirm_key(id), Wire.question(confirm, %{"passage" => Wire.text_path(as, id)}, [])}
      end

    fallback = for %Passage{id: id} <- passages, do: Wire.text_path(as, id)

    %{
      "state" => %{as => Wire.passages(passages, show)},
      "questions" => Map.merge(confirms, descriptor_questions(run.terms, fallback))
    }
  end

  @doc """
  Folds judged findings into the run, as `Cite.Screen.resolve/2` does for
  round 1. It sets `findings`, adds one `Cite.Error` per failed request, and
  adds each reply's usage and model to the run's. The run's `review_band`,
  `{low, high}`, sets the verdicts.

  Each confirm drops its passage at or below `low`, cites it for review below
  `high`, and holds it at or above. A passage filling a role holds, once. A
  finding fails on an asked check at or below `low` or with nothing left to
  cite, holds when every asked check is at or above `high` and a citation
  holds, and is sent to review otherwise.
  """
  @spec resolve(Run.t(), [outcome()]) :: Run.t()
  def resolve(%Run{} = run, outcomes) do
    findings =
      for {gathered, {:ok, verdict}} <- outcomes,
          do: finding(gathered, verdict.answers, run.terms, run.review_band)

    errors = for {gathered, {:error, reason}} <- outcomes, do: error(gathered, reason)
    usages = for {_gathered, {:ok, verdict}} <- outcomes, do: verdict.usage
    models = for {_gathered, {:ok, %{model: model}}} <- outcomes, do: model

    %{
      run
      | findings: findings,
        errors: run.errors ++ errors,
        usages: run.usages ++ usages,
        models: run.models ++ models
    }
  end

  defp finding(%Gathered{concern: concern} = gathered, answers, terms, {low, high}) do
    checks =
      for %Check{name: name} <- asked(gathered),
          into: %{},
          do: {name, answers[Atom.to_string(name)]}

    {evidence, dropped} = citations(gathered, answers, {low, high})

    %Finding{
      concern: concern.name,
      category: concern.category,
      verdict: verdict(Map.values(checks), evidence, {low, high}),
      checks: checks,
      descriptors:
        Map.new(terms.descriptors, fn {name, _question} ->
          {name, answers[Atom.to_string(name)]}
        end),
      evidence: evidence,
      dropped: dropped
    }
  end

  # A check is asked when every role it names is filled and, if distinct,
  # those roles are different passages.
  defp asked(%Gathered{concern: %Concern{checks: checks}, roles: roles}) do
    Enum.filter(checks, fn %Check{roles: named, distinct: distinct} ->
      filled = Enum.map(named, &Map.get(roles, &1))

      nil not in filled and
        (not distinct or length(Enum.uniq_by(filled, & &1.id)) == length(filled))
    end)
  end

  defp descriptor_questions(%Terms{descriptors: descriptors}, fallback) do
    Map.new(descriptors, fn {name, question} ->
      {Atom.to_string(name), Wire.question(question, %{}, fallback)}
    end)
  end

  defp citations(
         %Gathered{concern: %Concern{detect: nil}, passages: passages},
         _answers,
         _band
       ) do
    {Enum.map(passages, &%Citation{passage: &1, verdict: :holds, answer: nil}), []}
  end

  defp citations(%Gathered{passages: passages}, answers, band) do
    passages
    |> Enum.map(fn %Passage{id: id} = passage ->
      answer = answers[confirm_key(id)]

      %Citation{
        passage: passage,
        verdict: confirm_verdict(Answer.noul(answer), band),
        answer: answer
      }
    end)
    |> Enum.split_with(&(&1.verdict != :dropped))
  end

  defp confirm_verdict(noul, {low, _high}) when noul <= low, do: :dropped
  defp confirm_verdict(noul, {_low, high}) when noul < high, do: :review
  defp confirm_verdict(_noul, _band), do: :holds

  defp verdict(check_answers, evidence, {low, high}) do
    nouls = Enum.map(check_answers, &Answer.noul/1)

    cond do
      evidence == [] or Enum.any?(nouls, &(&1 <= low)) -> :fails
      Enum.all?(nouls, &(&1 >= high)) and Enum.any?(evidence, &(&1.verdict == :holds)) -> :holds
      true -> :review
    end
  end

  defp error(%Gathered{concern: concern, passages: passages}, reason) do
    %Error{concern: concern.name, passage_ids: Enum.map(passages, & &1.id), reason: reason}
  end

  defp confirm_key(id), do: "confirm:" <> id
end
