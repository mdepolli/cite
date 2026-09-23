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
         :ok <- check_indicator_placeholders(entities),
         :ok <- check_concern_shapes(entities),
         :ok <- check_member_placement(entities),
         :ok <- check_roles(entities),
         :ok <- check_check_placeholders(entities),
         :ok <- check_always_asked(entities),
         :ok <- check_distinct_arity(entities),
         :ok <- check_descriptors(entities),
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
    indicators =
      for %struct{} = entity <- entities,
          struct in [Dsl.Filter, Dsl.Concern, Dsl.Factor],
          do: entity

    checks = for {_concern, check} <- checks(entities), do: check

    descriptors =
      for %struct{} = entity <- entities, struct in [Dsl.Score, Dsl.Choice], do: entity

    descriptor_names = Enum.map(descriptors, & &1.name)

    with :ok <-
           first_error(
             repeats(indicators),
             &{"indicator name #{inspect(&1.name)} is declared twice", [&1.name], &1}
           ),
         :ok <-
           first_error(
             repeats(descriptors),
             &{"descriptor name #{inspect(&1.name)} is declared twice", [&1.name], &1}
           ),
         :ok <-
           first_error(
             Enum.filter(indicators ++ checks ++ descriptors, &colon?(&1.name)),
             &{~s(names must not contain ":", got #{inspect(&1.name)}), [&1.name], &1}
           ) do
      first_error(
        Enum.filter(checks, &(&1.name in descriptor_names)),
        &{"#{inspect(&1.name)} names both a check and a descriptor", [&1.name], &1}
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
          {"concern #{inspect(concern)} declares #{kind} #{inspect(twice.name)} twice",
           [concern, twice.name], twice}
      end
    end)
  end

  defp check_criteria(entities) do
    entities
    |> nouls()
    |> first_error(fn {_kind, label, noul, path} ->
      if noul.yes && noul.no, do: nil, else: {"#{label} needs yes and no", path, noul}
    end)
  end

  defp check_indicator_placeholders(entities) do
    entities
    |> nouls()
    |> Enum.reject(fn {kind, _label, _noul, _path} -> kind == :check end)
    |> first_error(fn {_kind, label, noul, path} -> passage_only(label, noul, path) end)
  end

  defp check_concern_shapes(entities) do
    first_error(concerns(entities), fn %Dsl.Concern{name: name} = concern ->
      if is_nil(concern.indicator) == (concern.roles == []),
        do: {"concern #{inspect(name)} needs an indicator or roles, not both", [name], concern}
    end)
  end

  # A fit is asked only of a concern screened directly, and checks only of a
  # concern built from roles; anywhere else either would compile and never be
  # asked.
  defp check_member_placement(entities) do
    first_error(concerns(entities), fn
      %Dsl.Concern{name: name, fit: fit, roles: [_ | _]} when not is_nil(fit) ->
        {"concern #{inspect(name)}: a fit applies only to a concern with an indicator", [name],
         fit}

      %Dsl.Concern{name: name, checks: [check | _], roles: []} ->
        {"concern #{inspect(name)}: checks apply only to a concern built from roles", [name],
         check}

      _concern ->
        nil
    end)
  end

  defp check_roles(entities) do
    factors = for %Dsl.Factor{name: name} <- entities, do: name

    first_error(for(concern <- concerns(entities), role <- concern.roles, do: {concern, role}), fn
      {concern, %Dsl.Role{name: :passage} = role} ->
        {"concern #{inspect(concern.name)}: a role cannot be named :passage", [concern.name],
         role}

      {concern, %Dsl.Role{name: name, factor: factor} = role} ->
        unless factor in factors,
          do:
            {"role #{inspect(name)} names factor #{inspect(factor)}, which the policy does not declare",
             [concern.name, name], role}
    end)
  end

  defp check_check_placeholders(entities) do
    first_error(checks(entities), fn {concern, check} ->
      roles = Enum.map(concern.roles, &Atom.to_string(&1.name))
      named = placeholders(check)

      cond do
        named == [] ->
          {"check #{inspect(check.name)} must use at least one of its concern's roles",
           [concern.name, check.name], check}

        (unknown = named -- roles) != [] ->
          {"check #{inspect(check.name)} names unknown role {#{hd(unknown)}}",
           [concern.name, check.name], check}

        true ->
          nil
      end
    end)
  end

  defp check_always_asked(entities) do
    entities
    |> concerns()
    |> Enum.filter(&(&1.roles != []))
    |> first_error(fn concern ->
      required =
        for %Dsl.Role{optional: false, name: name} <- concern.roles, do: Atom.to_string(name)

      unless Enum.any?(concern.checks, &(not &1.distinct and placeholders(&1) -- required == [])),
        do:
          {"concern #{inspect(concern.name)} needs a check that names only required roles and is not distinct",
           [concern.name], concern}
    end)
  end

  defp check_distinct_arity(entities) do
    first_error(checks(entities), fn {concern, check} ->
      if check.distinct and length(placeholders(check)) < 2,
        do:
          {"distinct check #{inspect(check.name)} must name at least two roles",
           [concern.name, check.name], check}
    end)
  end

  defp check_descriptors(entities) do
    first_error(entities, fn
      %Dsl.Score{name: name} = score ->
        cond do
          placeholders(score) != [] ->
            {"descriptor #{inspect(name)} must not use placeholders", [name], score}

          length(score.levels) not in 2..10 or Enum.uniq(score.levels) != score.levels ->
            {"score #{inspect(name)} needs 2 to 10 unique levels", [name], score}

          true ->
            nil
        end

      %Dsl.Choice{name: name} = choice ->
        keys = Enum.map(choice.options, & &1.key)

        cond do
          placeholders(choice) != [] ->
            {"descriptor #{inspect(name)} must not use placeholders", [name], choice}

          keys == [] or Enum.uniq(keys) != keys ->
            {"choice #{inspect(name)} needs at least one option, with unique keys", [name],
             choice}

          true ->
            nil
        end

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

    Enum.reject(
      [
        concern.indicator &&
          {:indicator, "#{label} indicator", concern.indicator, [name, :indicator]},
        concern.fit && {:fit, "#{label} fit", concern.fit, [name, :fit]}
      ],
      &is_nil/1
    ) ++
      for(
        check <- concern.checks,
        do: {:check, "check #{inspect(check.name)}", check, [name, check.name]}
      )
  end

  defp passage_only(label, noul, path) do
    in_question = Placeholder.names(noul.question)

    cond do
      (other = placeholders(noul) -- ["passage"]) != [] ->
        {"#{label} may only use {passage}, got {#{hd(other)}}", path, noul}

      "passage" not in in_question ->
        {"#{label} must use {passage}", path, noul}

      true ->
        nil
    end
  end

  defp concerns(entities), do: for(%Dsl.Concern{} = concern <- entities, do: concern)

  defp checks(entities),
    do: for(concern <- concerns(entities), check <- concern.checks, do: {concern, check})

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

  # The first item the rule rejects, as {:error, message, path, entity}, where
  # entity is the declaration to point at; :ok if none.
  defp first_error(items, rule) do
    Enum.find_value(items, :ok, fn item ->
      case rule.(item) do
        nil -> nil
        {message, path, entity} -> {:error, message, path, entity}
      end
    end)
  end

  defp location(nil), do: nil
  defp location(entity), do: Entity.anno(entity)
end
