defmodule Cite.Policy.Build do
  @moduledoc """
  Compiles a policy's declarations to its `Cite.Policy.Terms`, the data the
  rounds read, persists them on the module, and reads them back (`read/1`). A Spark
  persister: it runs after `Cite.Policy.Checks`, so every declaration it sees
  is valid. Internal.
  """

  use Spark.Dsl.Transformer

  alias Cite.Placeholder
  alias Cite.Policy.{Check, Concern, Dsl, Question, Role, Terms}
  alias Spark.Dsl.{Extension, Transformer}

  @key :cite_policy

  @doc """
  The terms of a module that uses `Cite.Policy`. Raises
  `ArgumentError` for any other module.
  """
  @spec read(module()) :: Terms.t()
  def read(module) when is_atom(module) do
    case persisted_terms(module) do
      %Terms{} = terms ->
        terms

      nil ->
        raise ArgumentError, "#{inspect(module)} is not a Cite policy; it must `use Cite.Policy`"
    end
  end

  # A module is a policy exactly when it carries the terms this module
  # persisted. Asking that, rather than naming Cite.Policy, keeps Build free of
  # a reference back to the module whose compilation runs it.
  defp persisted_terms(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :spark_dsl_config, 0),
      do: Extension.get_persisted(module, @key),
      else: nil
  end

  @impl true
  def transform(dsl) do
    entities = Transformer.get_entities(dsl, [:policy])

    terms = %Terms{
      exclusive: Transformer.get_option(dsl, [:policy], :exclusive, false),
      filters: for(%Dsl.Filter{} = filter <- entities, do: {filter.name, noul(filter)}),
      concerns: for(%Dsl.Concern{} = concern <- entities, do: concern(concern)),
      factors: for(%Dsl.Factor{} = factor <- entities, do: {factor.name, noul(factor)}),
      descriptors:
        for(
          %struct{} = entity <- entities,
          struct in [Dsl.Score, Dsl.Choice],
          do: descriptor(entity)
        )
    }

    {:ok, Transformer.persist(dsl, @key, terms)}
  end

  defp concern(%Dsl.Concern{} = concern) do
    roles = Enum.map(concern.roles, &role/1)
    role_names = Enum.map(roles, &Atom.to_string(&1.name))
    indicator = concern.indicator && noul(concern.indicator)

    %Concern{
      name: concern.name,
      category: concern.category || concern.name,
      indicator: indicator,
      fit: (concern.fit && noul(concern.fit)) || indicator,
      roles: roles,
      checks: Enum.map(concern.checks, &check(&1, role_names))
    }
  end

  defp role(%Dsl.Role{} = role) do
    %Role{name: role.name, factor: role.factor, optional: role.optional, distinct: role.distinct}
  end

  defp check(%Dsl.Noul{} = check, role_names) do
    # The focus expands too, so a role it names must be filled for the check
    # to be asked.
    roles =
      [check.question, check.focus]
      |> Placeholder.names()
      |> Enum.filter(&(&1 in role_names))
      |> Enum.map(&String.to_existing_atom/1)

    %Check{name: check.name, distinct: check.distinct, roles: roles, question: noul(check)}
  end

  defp noul(%{question: _, focus: _, yes: _, no: _} = noul) do
    %Question{
      type: :noul,
      text: noul.question,
      focus: noul.focus,
      criteria: %{true: criterion(noul.yes), false: criterion(noul.no)}
    }
  end

  defp criterion(%Dsl.Criterion{} = criterion) do
    for {key, value} <- [
          what: criterion.what,
          not_for: criterion.not_for,
          examples: criterion.examples
        ],
        value != nil,
        into: %{},
        do: {key, value}
  end

  defp descriptor(%Dsl.Score{} = score) do
    {score.name,
     %Question{type: :score, text: score.question, focus: score.focus, criteria: score.levels}}
  end

  defp descriptor(%Dsl.Choice{} = choice) do
    criteria = Map.new(choice.options, &{Atom.to_string(&1.key), &1.description})

    {choice.name,
     %Question{type: :choice, text: choice.question, focus: choice.focus, criteria: criteria}}
  end
end
