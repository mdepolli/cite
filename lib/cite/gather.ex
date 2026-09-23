defmodule Cite.Gather do
  @moduledoc """
  Between the rounds, no model call: the screen's scores become the findings
  to judge, by fixed rules. Pure. Internal.
  """

  alias Cite.{Gathered, Passage, Run}
  alias Cite.Policy.{Concern, Role, Terms}

  @doc """
  The run's `gathered` findings, to judge in the policy's concern order. A
  passage counts only if it passes every filter; a directly screened concern
  gathers every match (the strongest `max_evidence` of them); a concern
  built from factors fills each role with its strongest match, and needs
  every required role.
  """
  @spec findings(Run.t()) :: Run.t()
  def findings(%Run{screen: screen} = run) when is_map(screen) do
    terms = run.terms
    threshold = run.threshold

    eligible = Enum.filter(run.source.passages, &passes_filters?(screen[&1.id], terms, threshold))
    direct = direct_matches(terms, eligible, screen, threshold)

    gathered =
      Enum.flat_map(terms.concerns, fn
        %Concern{detect: nil} = concern ->
          built(concern, eligible, screen, threshold)

        %Concern{} = concern ->
          screened(concern, Map.get(direct, concern.name, []), screen, run.max_evidence)
      end)

    %{run | gathered: gathered}
  end

  # A passage whose window failed has no row, and so passes nothing.
  defp passes_filters?(nil, _terms, _threshold), do: false

  defp passes_filters?(row, %Terms{filters: filters}, threshold) do
    Enum.all?(filters, fn {name, _question} -> above?(row, name, threshold) end)
  end

  # Each directly screened concern's matching passages. Under `exclusive` a
  # passage stays only with its highest-scoring concern; `Enum.max_by/2`
  # keeps the first of equals, so a tie goes to the concern declared first.
  defp direct_matches(%Terms{} = terms, eligible, screen, threshold) do
    names = for %Concern{detect: detect, name: name} <- terms.concerns, detect, do: name

    pairs =
      for %Passage{id: id} = passage <- eligible,
          matched = Enum.filter(names, &above?(screen[id], &1, threshold)),
          matched != [],
          name <- keep(matched, screen[id], terms.exclusive),
          do: {name, passage}

    Enum.group_by(pairs, &elem(&1, 0), &elem(&1, 1))
  end

  defp keep(matched, _row, false), do: matched
  defp keep(matched, row, true), do: [Enum.max_by(matched, &row[&1])]

  defp screened(_concern, [], _screen, _max_evidence), do: []

  defp screened(%Concern{name: name} = concern, matches, screen, max_evidence) do
    {kept, over_cap} =
      matches
      |> Enum.sort_by(&screen[&1.id][name], :desc)
      |> Enum.split(max_evidence)

    [
      %Gathered{
        concern: concern,
        passages: in_order(kept, matches),
        over_cap: in_order(over_cap, matches)
      }
    ]
  end

  # Roles that need not be distinct are filled first, so a distinct role can
  # avoid every passage already in one.
  defp built(%Concern{roles: roles} = concern, eligible, screen, threshold) do
    {distinct, shared} = Enum.split_with(roles, & &1.distinct)
    filled = Enum.reduce(shared ++ distinct, %{}, &fill(&1, &2, eligible, screen, threshold))

    if Enum.all?(roles, &(&1.optional or Map.has_key?(filled, &1.name))) do
      used =
        filled
        |> Map.values()
        |> Enum.uniq_by(& &1.id)

      [%Gathered{concern: concern, passages: in_order(used, eligible), roles: filled}]
    else
      []
    end
  end

  defp fill(%Role{} = role, filled, eligible, screen, threshold) do
    taken = if role.distinct, do: Enum.map(Map.values(filled), & &1.id), else: []

    best =
      eligible
      |> Enum.filter(&(above?(screen[&1.id], role.factor, threshold) and &1.id not in taken))
      |> Enum.max_by(&screen[&1.id][role.factor], fn -> nil end)

    if best, do: Map.put(filled, role.name, best), else: filled
  end

  # A score is compared only when present: in term order `nil` sorts above
  # every number, so a missing score would otherwise count as a match.
  defp above?(row, name, threshold) do
    case row do
      %{^name => score} -> score > threshold
      _missing -> false
    end
  end

  defp in_order(subset, ordered) do
    ids = MapSet.new(subset, & &1.id)
    Enum.filter(ordered, &MapSet.member?(ids, &1.id))
  end
end
