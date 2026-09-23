defmodule Cite.GatherTest do
  use ExUnit.Case, async: true

  alias Cite.{Gather, Source}
  alias Cite.TestTerms

  defp gather(terms, screen, opts \\ []) do
    ids = screen |> Map.keys() |> Enum.sort()
    source = Source.new(Enum.map(ids, &%{id: &1, text: "text of #{&1}"}), as: "utterances")

    Gather.findings(
      terms,
      source,
      screen,
      Keyword.merge([threshold: 0.5, max_evidence: 20], opts)
    )
  end

  # Each finding as {concern, cited ids, over-cap ids, %{role => id}}.
  defp summary(findings) do
    for finding <- findings do
      {finding.concern.name, Enum.map(finding.passages, & &1.id),
       Enum.map(finding.over_cap, & &1.id),
       Map.new(finding.roles, fn {role, p} -> {role, p.id} end)}
    end
  end

  # A screen row for a passage the client_speaking filter lets through.
  defp spoken_by_client(scores), do: Map.put(scores, :client_speaking, 0.95)

  describe "filters" do
    test "a passage failing a filter is evidence for nothing" do
      # Arrange
      screen = %{"U1" => %{client_speaking: 0.2, cashflow_stress: 0.9}}

      # Act + Assert
      assert summary(gather(TestTerms.household(), screen)) == []
    end

    test "a passage whose window failed has no row and is evidence for nothing" do
      # Arrange
      screen = %{"U1" => spoken_by_client(%{cashflow_stress: 0.9})}
      source = Source.new([%{id: "U0", text: "lost"}, %{id: "U1", text: "kept"}])

      findings =
        Gather.findings(TestTerms.household(), source, screen,
          threshold: 0.5,
          max_evidence: 20
        )

      # Act + Assert
      assert summary(findings) == [{:cashflow_stress, ["U1"], [], %{}}]
    end
  end

  describe "directly screened concerns" do
    test "gather every match above threshold, in source order" do
      # Arrange
      screen = %{
        "U2" => spoken_by_client(%{cashflow_stress: 0.7}),
        "U1" => spoken_by_client(%{cashflow_stress: 0.9}),
        "U3" => spoken_by_client(%{cashflow_stress: 0.5})
      }

      # Act + Assert
      assert summary(gather(TestTerms.household(), screen)) == [
               {:cashflow_stress, ["U1", "U2"], [], %{}}
             ]
    end

    test "past max_evidence keep the strongest and record the rest as over_cap" do
      # Arrange
      screen = %{
        "U1" => spoken_by_client(%{cashflow_stress: 0.6}),
        "U2" => spoken_by_client(%{cashflow_stress: 0.9}),
        "U3" => spoken_by_client(%{cashflow_stress: 0.8})
      }

      # Act + Assert
      assert summary(gather(TestTerms.household(), screen, max_evidence: 2)) ==
               [{:cashflow_stress, ["U2", "U3"], ["U1"], %{}}]
    end
  end

  describe "exclusive" do
    test "keeps a passage only with its highest-scoring direct concern" do
      # Arrange
      screen = %{"U1" => spoken_by_client(%{health: 0.6, life_event: 0.8})}

      # Act + Assert
      assert summary(gather(TestTerms.two_concerns(), screen)) == [{:life_event, ["U1"], [], %{}}]
    end

    test "breaks a tie by concern declaration order" do
      # Arrange
      screen = %{"U1" => spoken_by_client(%{health: 0.8, life_event: 0.8})}

      # Act + Assert
      assert summary(gather(TestTerms.two_concerns(), screen)) == [{:health, ["U1"], [], %{}}]
    end

    test "leaves other passages with their own concerns" do
      # Arrange
      screen = %{
        "U1" => spoken_by_client(%{health: 0.9, life_event: 0.6}),
        "U2" => spoken_by_client(%{health: 0.1, life_event: 0.7})
      }

      # Act + Assert
      assert summary(gather(TestTerms.two_concerns(), screen)) ==
               [{:health, ["U1"], [], %{}}, {:life_event, ["U2"], [], %{}}]
    end
  end

  describe "concerns built from factors" do
    test "fill each role with its strongest match, citing the role passages in source order" do
      # Arrange
      screen = %{
        "U1" => spoken_by_client(%{dependents: 0.7}),
        "U2" => spoken_by_client(%{dependents: 0.9}),
        "U3" => spoken_by_client(%{primary_income: 0.8})
      }

      # Act + Assert
      assert summary(gather(TestTerms.household(), screen)) ==
               [{:household_income, ["U2", "U3"], [], %{household: "U2", income: "U3"}}]
    end

    test "a distinct role skips passages that fill another role" do
      # Arrange
      screen = %{
        "U1" => spoken_by_client(%{dependents: 0.9}),
        "U2" => spoken_by_client(%{primary_income: 0.9, other_household_income: 0.95}),
        "U3" => spoken_by_client(%{other_household_income: 0.6})
      }

      # Act + Assert
      assert summary(gather(TestTerms.household(), screen)) == [
               {:household_income, ["U1", "U2", "U3"], [],
                %{household: "U1", income: "U2", other_earner: "U3"}}
             ]
    end

    test "one passage may fill two non-distinct roles, and is cited once" do
      # Arrange
      screen = %{"U1" => spoken_by_client(%{dependents: 0.9, primary_income: 0.9})}

      # Act + Assert
      assert summary(gather(TestTerms.household(), screen)) ==
               [{:household_income, ["U1"], [], %{household: "U1", income: "U1"}}]
    end

    test "an empty required role means no finding" do
      # Arrange
      screen = %{"U1" => spoken_by_client(%{dependents: 0.9})}

      # Act + Assert
      assert summary(gather(TestTerms.household(), screen)) == []
    end
  end

  test "findings follow the policy's concern order" do
    # Arrange
    screen = %{
      "U1" => spoken_by_client(%{dependents: 0.9, primary_income: 0.9}),
      "U2" => spoken_by_client(%{cashflow_stress: 0.8})
    }

    # Act + Assert
    assert summary(gather(TestTerms.household(), screen)) == [
             {:cashflow_stress, ["U2"], [], %{}},
             {:household_income, ["U1"], [], %{household: "U1", income: "U1"}}
           ]
  end
end
