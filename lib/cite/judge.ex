defmodule Cite.Judge do
  @moduledoc """
  Round 2, minus the client call: a gathered finding becomes one request on
  its own evidence, and the reply becomes a `Cite.Finding` under the verdict
  rules. Pure. Internal.
  """

  alias Cite.{Citation, Error, Finding, Passage, Source, Wire}
  alias Cite.Gather.Finding, as: Gathered
  alias Cite.Policy.{Check, Concern, Role, Terms}

  @type band :: {number(), number()}
  @type outcome :: {Gathered.t(), {:ok, Cite.verdict()} | {:error, term()}}

  @doc """
  The round-2 request. A directly screened concern: its passages under the
  source's `as`, a fit per passage keyed `"fit:<id>"`, the descriptors over
  all of them. A concern built from factors: each role at the top level, the
  checks that apply, the descriptors over every role.
  """
  @spec request(Gathered.t(), Source.t(), Terms.t()) :: map()
  def request(
        %Gathered{concern: %Concern{indicator: nil}} = gathered,
        %Source{show: show},
        terms
      ) do
    state =
      Map.new(gathered.roles, fn {role, passage} ->
        {Atom.to_string(role), Wire.passage(passage, show)}
      end)

    paths =
      Map.new(gathered.roles, fn {role, _passage} -> {Atom.to_string(role), "#{role}.text"} end)

    fallback =
      for %Role{name: role} <- gathered.concern.roles,
          Map.has_key?(gathered.roles, role),
          do: "#{role}.text"

    checks =
      for %Check{} = check <- asked(gathered), into: %{} do
        {Atom.to_string(check.name), Wire.question(check.question, paths, [])}
      end

    %{"state" => state, "questions" => Map.merge(checks, descriptor_questions(terms, fallback))}
  end

  def request(
        %Gathered{concern: %Concern{fit: fit}, passages: passages},
        %Source{as: as, show: show},
        terms
      ) do
    fits =
      for %Passage{id: id} <- passages, into: %{} do
        {fit_key(id), Wire.question(fit, %{"passage" => "#{as}.#{id}.text"}, [])}
      end

    fallback = for %Passage{id: id} <- passages, do: "#{as}.#{id}.text"

    %{
      "state" => %{as => Wire.passages(passages, show)},
      "questions" => Map.merge(fits, descriptor_questions(terms, fallback))
    }
  end

  @doc """
  Folds judged findings into `Cite.Finding`s, one `Cite.Error` per failed
  request, and the usage and model of each reply, as `Cite.Screen.resolve/2`
  does for round 1. Options: `review_band` (`{low, high}`, required).

  Each fit drops its passage at or below `low`, cites it for review below
  `high`, and holds it at or above. A passage filling a role holds, once. A
  finding fails on an asked check at or below `low` or with nothing left to
  cite, holds when every asked check is at or above `high` and a citation
  holds, and is sent to review otherwise.
  """
  @spec resolve([outcome()], Terms.t(), keyword()) :: %{
          findings: [Finding.t()],
          errors: [Error.t()],
          usages: [Cite.usage() | nil],
          models: [String.t()]
        }
  def resolve(outcomes, %Terms{} = terms, opts) do
    review_band = Keyword.fetch!(opts, :review_band)

    %{
      findings:
        for(
          {gathered, {:ok, verdict}} <- outcomes,
          do: finding(gathered, verdict.answers, terms, review_band)
        ),
      errors: for({gathered, {:error, reason}} <- outcomes, do: error(gathered, reason)),
      usages: for({_gathered, {:ok, verdict}} <- outcomes, do: verdict.usage),
      models: for({_gathered, {:ok, %{model: model}}} <- outcomes, do: model)
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
      dropped: dropped,
      over_cap: gathered.over_cap
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
         %Gathered{concern: %Concern{indicator: nil}, passages: passages},
         _answers,
         _band
       ) do
    {Enum.map(passages, &%Citation{passage: &1, verdict: :holds, answer: nil}), []}
  end

  defp citations(%Gathered{passages: passages}, answers, band) do
    passages
    |> Enum.map(fn %Passage{id: id} = passage ->
      answer = answers[fit_key(id)]
      %Citation{passage: passage, verdict: fit_verdict(answer["noul"], band), answer: answer}
    end)
    |> Enum.split_with(&(&1.verdict != :dropped))
  end

  defp fit_verdict(noul, {low, _high}) when noul <= low, do: :dropped
  defp fit_verdict(noul, {_low, high}) when noul < high, do: :review
  defp fit_verdict(_noul, _band), do: :holds

  defp verdict(check_answers, evidence, {low, high}) do
    nouls = Enum.map(check_answers, & &1["noul"])

    cond do
      evidence == [] or Enum.any?(nouls, &(&1 <= low)) -> :fails
      Enum.all?(nouls, &(&1 >= high)) and Enum.any?(evidence, &(&1.verdict == :holds)) -> :holds
      true -> :review
    end
  end

  defp error(%Gathered{concern: concern, passages: passages}, reason) do
    %Error{concern: concern.name, passage_ids: Enum.map(passages, & &1.id), reason: reason}
  end

  defp fit_key(id), do: "fit:" <> id
end
