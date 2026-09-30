defmodule Cite.GatherTest do
  use ExUnit.Case, async: true

  alias Cite.{Gather, Source, TestRun, TestTerms}

  # Gathers from a run whose source holds one passage per screen row, in id
  # order; `fields` override the run's defaults.
  defp gather(terms, screen, fields \\ []) do
    ids =
      screen
      |> Map.keys()
      |> Enum.sort()

    source = Source.new(Enum.map(ids, &%{id: &1, text: "text of #{&1}"}), as: "utterances")
    run = TestRun.new(terms, [source: source, screen: screen] ++ fields)

    Gather.findings(run).gathered
  end

  # Each finding as {concern, cited ids, %{role => id}}.
  defp summary(findings) do
    for finding <- findings do
      {finding.concern.name, Enum.map(finding.passages, & &1.id),
       Map.new(finding.roles, fn {role, p} -> {role, p.id} end)}
    end
  end

  # A screen row for a passage the client_speaking filter lets through.
  defp spoken_by_client(scores), do: Map.put(scores, :client_speaking, 0.95)

  describe "filters" do
    test "a passage failing a filter is evidence for nothing" do
      screen = %{"U1" => %{client_speaking: 0.2, cashflow_stress: 0.9}}

      assert summary(gather(TestTerms.household(), screen)) == []
    end

    test "a passage whose window failed has no row and is evidence for nothing" do
      screen = %{"U1" => spoken_by_client(%{cashflow_stress: 0.9})}
      source = Source.new([%{id: "U0", text: "lost"}, %{id: "U1", text: "kept"}])
      run = Gather.findings(TestRun.new(TestTerms.household(), source: source, screen: screen))

      assert summary(run.gathered) == [{:cashflow_stress, ["U1"], %{}}]
    end
  end

  describe "directly screened concerns" do
    test "gathers every match strictly above threshold, in source order, not score order" do
      screen = %{
        "U2" => spoken_by_client(%{cashflow_stress: 0.9}),
        "U1" => spoken_by_client(%{cashflow_stress: 0.7}),
        "U3" => spoken_by_client(%{cashflow_stress: 0.5})
      }

      assert summary(gather(TestTerms.household(), screen)) == [
               {:cashflow_stress, ["U1", "U2"], %{}}
             ]
    end

    test "gathers every match, with no cap: twenty-five of them, in source order" do
      # Scores rise with the id, so score order would reverse the list.
      screen = Map.new(10..34, &{"U#{&1}", spoken_by_client(%{cashflow_stress: 0.5 + &1 / 100})})

      assert summary(gather(TestTerms.household(), screen)) == [
               {:cashflow_stress,
                ~w(U10 U11 U12 U13 U14 U15 U16 U17 U18 U19 U20 U21 U22 U23 U24 U25 U26 U27 U28 U29 U30 U31 U32 U33 U34),
                %{}}
             ]
    end

    test "reads the threshold from the run: a score above the default but below it is no match" do
      screen = %{
        "U1" => spoken_by_client(%{cashflow_stress: 0.7}),
        "U2" => spoken_by_client(%{cashflow_stress: 0.9})
      }

      assert summary(gather(TestTerms.household(), screen, threshold: 0.8)) == [
               {:cashflow_stress, ["U2"], %{}}
             ]
    end
  end

  describe "a passage matching several concerns" do
    test "is evidence for every directly screened concern it matches" do
      screen = %{
        "U1" => spoken_by_client(%{health: 0.6, life_event: 0.8}),
        "U2" => spoken_by_client(%{health: 0.1, life_event: 0.7})
      }

      assert summary(gather(TestTerms.two_concerns(), screen)) ==
               [{:health, ["U1"], %{}}, {:life_event, ["U1", "U2"], %{}}]
    end

    test "can fill a role beside its direct concern" do
      screen = %{
        "U1" => spoken_by_client(%{cashflow_stress: 0.9, dependents: 0.9, primary_income: 0.9})
      }

      assert summary(gather(TestTerms.household(), screen)) == [
               {:cashflow_stress, ["U1"], %{}},
               {:household_income, ["U1"], %{household: "U1", income: "U1"}}
             ]
    end
  end

  describe "concerns built from factors" do
    test "fills each role with its strongest match, citing the role passages in source order" do
      screen = %{
        "U1" => spoken_by_client(%{dependents: 0.7}),
        "U2" => spoken_by_client(%{dependents: 0.9}),
        "U3" => spoken_by_client(%{primary_income: 0.8})
      }

      assert summary(gather(TestTerms.household(), screen)) ==
               [{:household_income, ["U2", "U3"], %{household: "U2", income: "U3"}}]
    end

    test "a distinct role skips passages that fill another role" do
      screen = %{
        "U1" => spoken_by_client(%{dependents: 0.9}),
        "U2" => spoken_by_client(%{primary_income: 0.9, other_household_income: 0.95}),
        "U3" => spoken_by_client(%{other_household_income: 0.6})
      }

      assert summary(gather(TestTerms.household(), screen)) == [
               {:household_income, ["U1", "U2", "U3"],
                %{household: "U1", income: "U2", other_earner: "U3"}}
             ]
    end

    test "an empty required role means no finding" do
      screen = %{"U1" => spoken_by_client(%{dependents: 0.9})}

      assert summary(gather(TestTerms.household(), screen)) == []
    end
  end

  test "refuses a run that has not been screened" do
    assert_raise FunctionClauseError, fn ->
      Gather.findings(TestRun.new(TestTerms.household()))
    end
  end

  test "findings follow the policy's concern order" do
    screen = %{
      "U1" => spoken_by_client(%{dependents: 0.9, primary_income: 0.9}),
      "U2" => spoken_by_client(%{cashflow_stress: 0.8})
    }

    assert summary(gather(TestTerms.household(), screen)) == [
             {:cashflow_stress, ["U2"], %{}},
             {:household_income, ["U1"], %{household: "U1", income: "U1"}}
           ]
  end
end
