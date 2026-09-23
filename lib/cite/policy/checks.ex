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
  alias Spark.Dsl.Transformer
  alias Spark.Error.DslError

  @impl true
  def transform(dsl) do
    entities = Transformer.get_entities(dsl, [:policy])

    with :ok <- check_names(entities),
         :ok <- check_criteria(entities),
         :ok <- check_indicator_placeholders(entities),
         :ok <- check_concern_shapes(entities),
         :ok <- check_roles(entities),
         :ok <- check_check_placeholders(entities),
         :ok <- check_always_asked(entities),
         :ok <- check_distinct_arity(entities),
         :ok <- check_descriptors(entities) do
      {:ok, dsl}
    else
      {:error, message, path} ->
        module = Transformer.get_persisted(dsl, :module)
        {:error, DslError.exception(module: module, message: message, path: [:policy | path])}
    end
  end

  defp check_names(entities) do
    indicators =
      for %struct{name: name} <- entities,
          struct in [Dsl.Filter, Dsl.Concern, Dsl.Factor],
          do: name

    checks = for %Dsl.Concern{checks: checks} <- entities, check <- checks, do: check.name
    descriptors = for %struct{name: name} <- entities, struct in [Dsl.Score, Dsl.Choice], do: name

    with :ok <-
           first_error(
             indicators -- Enum.uniq(indicators),
             &{"indicator name #{inspect(&1)} is declared twice", [&1]}
           ),
         :ok <-
           first_error(
             Enum.filter(indicators ++ checks ++ descriptors, &colon?/1),
             &{~s(names must not contain ":", got #{inspect(&1)}), [&1]}
           ) do
      first_error(
        Enum.filter(checks, &(&1 in descriptors)),
        &{"#{inspect(&1)} names both a check and a descriptor", [&1]}
      )
    end
  end

  defp check_criteria(entities) do
    entities
    |> nouls()
    |> first_error(fn {_kind, label, noul, path} ->
      if noul.yes && noul.no, do: nil, else: {"#{label} needs yes and no", path}
    end)
  end

  defp check_indicator_placeholders(entities) do
    entities
    |> nouls()
    |> Enum.reject(fn {kind, _label, _noul, _path} -> kind == :check end)
    |> first_error(fn {_kind, label, noul, path} -> passage_only(label, noul, path) end)
  end

  defp check_concern_shapes(entities) do
    first_error(concerns(entities), fn %Dsl.Concern{
                                         name: name,
                                         indicator: indicator,
                                         roles: roles
                                       } ->
      if is_nil(indicator) == (roles == []),
        do: {"concern #{inspect(name)} needs an indicator or roles, not both", [name]}
    end)
  end

  defp check_roles(entities) do
    factors = for %Dsl.Factor{name: name} <- entities, do: name

    first_error(for(concern <- concerns(entities), role <- concern.roles, do: {concern, role}), fn
      {concern, %Dsl.Role{name: :passage}} ->
        {"concern #{inspect(concern.name)}: a role cannot be named :passage", [concern.name]}

      {concern, %Dsl.Role{name: name, factor: factor}} ->
        unless factor in factors,
          do:
            {"role #{inspect(name)} names factor #{inspect(factor)}, which the policy does not declare",
             [concern.name, name]}
    end)
  end

  defp check_check_placeholders(entities) do
    first_error(checks(entities), fn {concern, check} ->
      roles = Enum.map(concern.roles, &Atom.to_string(&1.name))
      named = placeholders(check)

      cond do
        named == [] ->
          {"check #{inspect(check.name)} must use at least one of its concern's roles",
           [concern.name, check.name]}

        (unknown = named -- roles) != [] ->
          {"check #{inspect(check.name)} names unknown role {#{hd(unknown)}}",
           [concern.name, check.name]}

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
           [concern.name]}
    end)
  end

  defp check_distinct_arity(entities) do
    first_error(checks(entities), fn {concern, check} ->
      if check.distinct and length(placeholders(check)) < 2,
        do:
          {"distinct check #{inspect(check.name)} must name at least two roles",
           [concern.name, check.name]}
    end)
  end

  defp check_descriptors(entities) do
    first_error(entities, fn
      %Dsl.Score{name: name} = score ->
        cond do
          placeholders(score) != [] ->
            {"descriptor #{inspect(name)} must not use placeholders", [name]}

          length(score.levels) not in 2..10 or Enum.uniq(score.levels) != score.levels ->
            {"score #{inspect(name)} needs 2 to 10 unique levels", [name]}

          true ->
            nil
        end

      %Dsl.Choice{name: name} = choice ->
        keys = Enum.map(choice.options, & &1.key)

        cond do
          placeholders(choice) != [] ->
            {"descriptor #{inspect(name)} must not use placeholders", [name]}

          keys == [] or Enum.uniq(keys) != keys ->
            {"choice #{inspect(name)} needs at least one option, with unique keys", [name]}

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
        {"#{label} may only use {passage}, got {#{hd(other)}}", path}

      "passage" not in in_question ->
        {"#{label} must use {passage}", path}

      true ->
        nil
    end
  end

  defp concerns(entities), do: for(%Dsl.Concern{} = concern <- entities, do: concern)

  defp checks(entities),
    do: for(concern <- concerns(entities), check <- concern.checks, do: {concern, check})

  # Placeholders expand in the question and the focus, so both are read.
  defp placeholders(%{question: question, focus: focus}) do
    Placeholder.names(question <> " " <> (focus || ""))
  end

  defp colon?(name), do: String.contains?(Atom.to_string(name), ":")

  # The first item the rule rejects, as {:error, message, path}; :ok if none.
  defp first_error(items, rule) do
    Enum.find_value(items, :ok, fn item ->
      case rule.(item) do
        nil -> nil
        {message, path} -> {:error, message, path}
      end
    end)
  end
end
