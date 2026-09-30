defmodule Cite.Policy.Checks do
  @moduledoc """
  The compile-time checks on a policy. A Spark transformer, not a verifier:
  Spark reports a failed verifier as a warning, and a mistake in a policy
  must stop the build. Runs before `Cite.Policy.Build`, so Build only ever
  sees a valid policy. Internal.
  """

  use Spark.Dsl.Transformer

  alias Cite.Placeholder
  alias Cite.Policy.Dsl
  alias Spark.Dsl.{Entity, Transformer}
  alias Spark.Error.DslError

  @impl true
  def transform(dsl) do
    entities = Transformer.get_entities(dsl, [:policy])

    with :ok <- check_names(entities),
         :ok <- check_member_names(entities),
         :ok <- check_criteria(entities),
         :ok <- check_detect_placeholders(entities),
         :ok <- check_concern_shapes(entities),
         :ok <- check_member_placement(entities),
         :ok <- check_roles(entities),
         :ok <- check_check_placeholders(entities),
         :ok <- check_required_role(entities),
         :ok <- check_always_asked(entities),
         :ok <- check_distinct_arity(entities),
         :ok <- check_descriptors(entities),
         :ok <- check_factors_used(entities),
         :ok <- check_has_concern(entities) do
      {:ok, dsl}
    else
      {:error, message, path, entity} ->
        {:error,
         DslError.exception(
           module: Transformer.get_persisted(dsl, :module),
           message: message,
           path: [:policy | path],
           location: location(entity)
         )}
    end
  end

  defp check_has_concern(entities) do
    if concerns(entities) == [],
      do:
        {:error, "a policy needs at least one concern: without one nothing can be found", [], nil},
      else: :ok
  end

  defp check_names(entities) do
    detects =
      for %struct{} = entity <- entities,
          struct in [Dsl.Filter, Dsl.Concern, Dsl.Factor],
          do: entity

    checks = for {_concern, check} <- checks(entities), do: check

    descriptors =
      for %struct{} = entity <- entities, struct in [Dsl.Score, Dsl.Choice], do: entity

    descriptor_names = Enum.map(descriptors, & &1.name)

    with :ok <-
           first_error(
             repeats(detects),
             &{:error, "detect name #{inspect(&1.name)} is declared twice", [&1.name], &1}
           ),
         :ok <-
           first_error(
             repeats(descriptors),
             &{:error, "descriptor name #{inspect(&1.name)} is declared twice", [&1.name], &1}
           ),
         :ok <-
           first_error(
             Enum.filter(detects ++ checks ++ descriptors, &colon?(&1.name)),
             &{:error, ~s(names must not contain ":", got #{inspect(&1.name)}), [&1.name], &1}
           ) do
      first_error(
        Enum.filter(checks, &(&1.name in descriptor_names)),
        &{:error, "#{inspect(&1.name)} names both a check and a descriptor", [&1.name], &1}
      )
    end
  end

  # Role and check names key the gathered roles, the request, and the
  # answers, so each must be unique within its concern.
  defp check_member_names(entities) do
    members =
      for %Dsl.Concern{name: concern} = entity <- concerns(entities),
          {kind, field} <- [role: :roles, check: :checks],
          do: {concern, kind, Map.fetch!(entity, field)}

    first_error(members, fn {concern, kind, members} ->
      case repeats(members) do
        [] ->
          nil

        [twice | _] ->
          {:error, "concern #{inspect(concern)} declares #{kind} #{inspect(twice.name)} twice",
           [concern, twice.name], twice}
      end
    end)
  end

  defp check_criteria(entities) do
    entities
    |> nouls()
    |> first_error(fn {_kind, label, noul, path} ->
      if noul.yes && noul.no, do: nil, else: {:error, "#{label} needs yes and no", path, noul}
    end)
  end

  defp check_detect_placeholders(entities) do
    entities
    |> nouls()
    |> Enum.reject(fn {kind, _label, _noul, _path} -> kind == :check end)
    |> first_error(fn {_kind, label, noul, path} -> passage_only(label, noul, path) end)
  end

  defp check_concern_shapes(entities) do
    first_error(concerns(entities), fn %Dsl.Concern{name: name} = concern ->
      if is_nil(concern.detect) == Enum.empty?(concern.roles),
        do:
          {:error, "concern #{inspect(name)} needs a detect or roles, not both", [name], concern}
    end)
  end

  # A confirm is asked only of a concern screened directly, and checks only of a
  # concern built from roles; anywhere else either would compile and never be
  # asked.
  defp check_member_placement(entities) do
    first_error(concerns(entities), fn
      %Dsl.Concern{name: name, confirm: confirm, roles: [_ | _]} when not is_nil(confirm) ->
        {:error, "concern #{inspect(name)}: a confirm applies only to a concern with a detect",
         [name], confirm}

      %Dsl.Concern{name: name, checks: [check | _], roles: []} ->
        {:error, "concern #{inspect(name)}: checks apply only to a concern built from roles",
         [name], check}

      _concern ->
        nil
    end)
  end

  defp check_roles(entities) do
    factors = for %Dsl.Factor{name: name} <- entities, do: name

    roles = for concern <- concerns(entities), role <- concern.roles, do: {concern, role}

    first_error(roles, fn
      {concern, %Dsl.Role{name: name, factor: factor} = role} ->
        cond do
          not Placeholder.name?(Atom.to_string(name)) ->
            {:error,
             "role #{inspect(name)} must be a word of letters, digits, and _: it is a placeholder and part of a path",
             [concern.name, name], role}

          name == :passage ->
            {:error, "concern #{inspect(concern.name)}: a role cannot be named :passage",
             [concern.name], role}

          factor not in factors ->
            {:error,
             "role #{inspect(name)} names factor #{inspect(factor)}, which the policy does not declare",
             [concern.name, name], role}

          true ->
            nil
        end
    end)
  end

  defp check_check_placeholders(entities) do
    first_error(checks(entities), fn {concern, check} ->
      roles = Enum.map(concern.roles, &Atom.to_string(&1.name))
      named = placeholders(check)

      cond do
        Placeholder.names(check.question) == [] ->
          {:error,
           "check #{inspect(check.name)} must name at least one of its concern's roles in its question",
           [concern.name, check.name], check}

        (unknown = named -- roles) != [] ->
          {:error, "check #{inspect(check.name)} names unknown role {#{hd(unknown)}}",
           [concern.name, check.name], check}

        true ->
          nil
      end
    end)
  end

  defp check_required_role(entities) do
    entities
    |> concerns()
    |> Enum.filter(&(&1.roles != []))
    |> first_error(fn concern ->
      if not Enum.any?(concern.roles, &(not &1.optional)),
        do:
          {:error, "concern #{inspect(concern.name)} needs at least one required role",
           [concern.name], concern}
    end)
  end

  defp check_always_asked(entities) do
    entities
    |> concerns()
    |> Enum.filter(&(&1.roles != []))
    |> first_error(fn concern ->
      required =
        for %Dsl.Role{optional: false, name: name} <- concern.roles, do: Atom.to_string(name)

      if not Enum.any?(concern.checks, &(not &1.distinct and placeholders(&1) -- required == [])),
        do:
          {:error,
           "concern #{inspect(concern.name)} needs a check that names only required roles and is not distinct",
           [concern.name], concern}
    end)
  end

  defp check_distinct_arity(entities) do
    first_error(checks(entities), fn {concern, check} ->
      if check.distinct and length(placeholders(check)) < 2,
        do:
          {:error, "distinct check #{inspect(check.name)} must name at least two roles",
           [concern.name, check.name], check}
    end)
  end

  defp check_descriptors(entities) do
    first_error(entities, fn
      %Dsl.Score{name: name} = score ->
        cond do
          placeholders(score) != [] ->
            {:error, "descriptor #{inspect(name)} must not use placeholders", [name], score}

          length(score.levels) not in 2..10 or Enum.uniq(score.levels) != score.levels ->
            {:error, "score #{inspect(name)} needs 2 to 10 unique levels", [name], score}

          true ->
            nil
        end

      %Dsl.Choice{name: name} = choice ->
        keys = Enum.map(choice.options, & &1.key)

        cond do
          placeholders(choice) != [] ->
            {:error, "descriptor #{inspect(name)} must not use placeholders", [name], choice}

          keys == [] or Enum.uniq(keys) != keys ->
            {:error, "choice #{inspect(name)} needs at least one option, with unique keys",
             [name], choice}

          true ->
            nil
        end

      _entity ->
        nil
    end)
  end

  # A factor is screened on every passage; one no role names costs a question
  # per passage and can never reach a finding.
  defp check_factors_used(entities) do
    used = for concern <- concerns(entities), role <- concern.roles, do: role.factor

    first_error(entities, fn
      %Dsl.Factor{name: name} = factor ->
        if name not in used,
          do:
            {:error,
             "factor #{inspect(name)} fills no role: it would be asked of every passage and never used",
             [name], factor}

      _entity ->
        nil
    end)
  end

  # Every yes/no question in the policy, labelled the way messages name it.
  defp nouls(entities) do
    Enum.flat_map(entities, fn
      %Dsl.Filter{name: name} = filter -> [{:filter, "filter #{inspect(name)}", filter, [name]}]
      %Dsl.Factor{name: name} = factor -> [{:factor, "factor #{inspect(name)}", factor, [name]}]
      %Dsl.Concern{} = concern -> concern_nouls(concern)
      _entity -> []
    end)
  end

  defp concern_nouls(%Dsl.Concern{name: name} = concern) do
    label = "concern #{inspect(name)}"

    checks =
      for check <- concern.checks,
          do: {:check, "check #{inspect(check.name)}", check, [name, check.name]}

    Enum.reject(
      [
        concern.detect &&
          {:detect, "#{label} detect", concern.detect, [name, :detect]},
        concern.confirm && {:confirm, "#{label} confirm", concern.confirm, [name, :confirm]}
      ],
      &is_nil/1
    ) ++ checks
  end

  defp passage_only(label, noul, path) do
    in_question = Placeholder.names(noul.question)

    cond do
      (other = placeholders(noul) -- ["passage"]) != [] ->
        {:error, "#{label} may only use {passage}, got {#{hd(other)}}", path, noul}

      "passage" not in in_question ->
        {:error, "#{label} must use {passage}", path, noul}

      true ->
        nil
    end
  end

  defp concerns(entities) do
    for %Dsl.Concern{} = concern <- entities, do: concern
  end

  defp checks(entities) do
    for concern <- concerns(entities), check <- concern.checks, do: {concern, check}
  end

  # Placeholders expand in the question and the focus, so both are read.
  defp placeholders(%{question: question, focus: focus}), do: Placeholder.names([question, focus])

  defp colon?(name), do: String.contains?(Atom.to_string(name), ":")

  # Each entity whose name an earlier one already took, in declaration order.
  defp repeats(entities) do
    {repeats, _seen} =
      Enum.flat_map_reduce(entities, MapSet.new(), fn entity, seen ->
        if MapSet.member?(seen, entity.name),
          do: {[entity], seen},
          else: {[], MapSet.put(seen, entity.name)}
      end)

    repeats
  end

  # The first error a rule returns, as {:error, message, path, entity} where
  # entity is the declaration to point at; :ok if the rule passes every item.
  defp first_error(items, rule), do: Enum.find_value(items, :ok, rule)

  defp location(nil), do: nil
  defp location(entity), do: Entity.anno(entity)
end
