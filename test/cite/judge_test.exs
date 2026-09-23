defmodule Cite.JudgeTest do
  use ExUnit.Case, async: true

  alias Cite.{Citation, Finding, Judge, Passage, Policy, Source}
  alias Cite.Gather.Finding, as: Gathered
  alias Cite.TestPolicies.Household
  alias Cite.Wire.Object

  @band {0.4, 0.6}

  setup do
    policy = Policy.compiled(Household)
    [cashflow, household] = policy.concerns

    %{
      policy: policy,
      source: Source.new([], as: "utterances", show: [:speaker]),
      cashflow: cashflow,
      household: household
    }
  end

  @u1 %Passage{id: "U1", text: "text of U1", meta: %{speaker: "B"}}
  @u2 %Passage{id: "U2", text: "text of U2", meta: %{speaker: "B"}}
  @u3 %Passage{id: "U3", text: "text of U3", meta: %{speaker: "B"}}
  @u4 %Passage{id: "U4", text: "text of U4", meta: %{speaker: "B"}}
  @u9 %Passage{id: "U9", text: "text of U9", meta: %{speaker: "B"}}

  # The model's descriptor answers, with the fits or checks each test adds.
  defp descriptors(extra) do
    Map.merge(
      %{
        "severity" => %{"score" => 1.2, "confidence" => 0.8},
        "temporal" => %{"choice" => "persistent", "confidence" => 0.9}
      },
      extra
    )
  end

  # Expected wire questions, spelled out: each helper is one literal.

  defp fit_u1 do
    %{
      "type" => "noul",
      "instructions" => %{
        "question" => "Does `utterances.U1.text` evidence that a shock could not be absorbed?",
        "inspect" => "`utterances.U1.text`"
      },
      "criteria" => %{
        "true" => %{"what" => "Costs look unmanageable now."},
        "false" => %{"what" => "Ordinary budget figures."}
      }
    }
  end

  defp fit_u2 do
    %{
      "type" => "noul",
      "instructions" => %{
        "question" => "Does `utterances.U2.text` evidence that a shock could not be absorbed?",
        "inspect" => "`utterances.U2.text`"
      },
      "criteria" => %{
        "true" => %{"what" => "Costs look unmanageable now."},
        "false" => %{"what" => "Ordinary budget figures."}
      }
    }
  end

  defp severity_over_u1_u2 do
    %{
      "type" => "score",
      "instructions" => %{
        "question" => "How much does this affect the speaker?",
        "focus" => "Judge the effect, not the topic.",
        "compare" => ["`utterances.U1.text`", "`utterances.U2.text`"]
      },
      "criteria" => ["In passing.", "It worries them.", "They cannot manage."]
    }
  end

  defp temporal_over_u1_u2 do
    %{
      "type" => "choice",
      "instructions" => %{
        "question" => "Is it temporary or lasting?",
        "compare" => ["`utterances.U1.text`", "`utterances.U2.text`"]
      },
      "criteria" => %{
        "transient" => "Expected to recover.",
        "persistent" => "Lasting.",
        "unknown" => "Not said."
      }
    }
  end

  defp severity_over_roles do
    %{
      "type" => "score",
      "instructions" => %{
        "question" => "How much does this affect the speaker?",
        "focus" => "Judge the effect, not the topic.",
        "compare" => ["`household.text`", "`income.text`"]
      },
      "criteria" => ["In passing.", "It worries them.", "They cannot manage."]
    }
  end

  defp temporal_over_roles do
    %{
      "type" => "choice",
      "instructions" => %{
        "question" => "Is it temporary or lasting?",
        "compare" => ["`household.text`", "`income.text`"]
      },
      "criteria" => %{
        "transient" => "Expected to recover.",
        "persistent" => "Lasting.",
        "unknown" => "Not said."
      }
    }
  end

  describe "request/3 for a directly screened concern" do
    test "asks the fit of each passage among its siblings, and the descriptors over all", ctx do
      # Arrange
      gathered = %Gathered{concern: ctx.cashflow, passages: [@u1, @u2]}

      # Act
      request = Judge.request(gathered, ctx.source, ctx.policy)

      # Assert
      assert request == %{
               "state" => %{
                 "utterances" =>
                   Object.new([
                     {"U1", %{"id" => "U1", "speaker" => "B", "text" => "text of U1"}},
                     {"U2", %{"id" => "U2", "speaker" => "B", "text" => "text of U2"}}
                   ])
               },
               "questions" => %{
                 "fit:U1" => fit_u1(),
                 "fit:U2" => fit_u2(),
                 "severity" => severity_over_u1_u2(),
                 "temporal" => temporal_over_u1_u2()
               }
             }
    end
  end

  describe "request/3 for a concern built from factors" do
    test "puts each role at the top level and asks the checks that apply", ctx do
      # Arrange
      gathered = %Gathered{
        concern: ctx.household,
        passages: [@u3, @u9],
        roles: %{household: @u3, income: @u9}
      }

      # Act
      request = Judge.request(gathered, ctx.source, ctx.policy)

      # Assert
      assert request == %{
               "state" => %{
                 "household" => %{"id" => "U3", "speaker" => "B", "text" => "text of U3"},
                 "income" => %{"id" => "U9", "speaker" => "B", "text" => "text of U9"}
               },
               "questions" => %{
                 "same_household" => %{
                   "type" => "noul",
                   "instructions" => %{
                     "question" =>
                       "Do `household.text` and `income.text` describe the same household?",
                     "compare" => ["`household.text`", "`income.text`"]
                   },
                   "criteria" => %{
                     "true" => %{"what" => "The same household."},
                     "false" => %{"what" => "Different people or occasions."}
                   }
                 },
                 "concentrated_income" => %{
                   "type" => "noul",
                   "instructions" => %{
                     "question" =>
                       "Given `household.text` and `income.text`, does one person's pay support the household?",
                     "compare" => ["`household.text`", "`income.text`"]
                   },
                   "criteria" => %{
                     "true" => %{"what" => "One main earner."},
                     "false" => %{"what" => "Two comparable earners."}
                   }
                 },
                 "severity" => severity_over_roles(),
                 "temporal" => temporal_over_roles()
               }
             }
    end

    test "skips a distinct check when its roles resolve to one passage", ctx do
      same = @u3

      gathered = %Gathered{
        concern: ctx.household,
        passages: [same],
        roles: %{household: same, income: same}
      }

      %{"questions" => questions} = Judge.request(gathered, ctx.source, ctx.policy)

      assert Enum.sort(Map.keys(questions)) == ["concentrated_income", "severity", "temporal"]
    end
  end

  describe "request/3 with a role named only in a check's focus" do
    test "skips that check while the role is empty, instead of failing to expand the focus",
         ctx do
      # Arrange
      policy = Policy.compiled(Cite.TestPolicies.FocusRole)
      [household] = policy.concerns

      gathered = %Gathered{
        concern: household,
        passages: [@u3, @u9],
        roles: %{household: @u3, income: @u9}
      }

      # Act
      %{"questions" => questions} = Judge.request(gathered, ctx.source, policy)

      # Assert
      assert Map.keys(questions) == ["same_household"]
    end
  end

  describe "resolve/4 for a directly screened concern" do
    test "drops, reviews, and holds each passage by its fit", ctx do
      # Arrange
      gathered = %Gathered{
        concern: ctx.cashflow,
        passages: [@u1, @u2, @u3],
        over_cap: [@u4]
      }

      answers =
        descriptors(%{
          "fit:U1" => %{"noul" => 0.4},
          "fit:U2" => %{"noul" => 0.59},
          "fit:U3" => %{"noul" => 0.6}
        })

      # Act
      finding = Judge.resolve(gathered, answers, ctx.policy, @band)

      # Assert
      assert finding == %Finding{
               concern: :cashflow_stress,
               category: :resilience,
               verdict: :holds,
               checks: %{},
               descriptors: %{
                 severity: %{"score" => 1.2, "confidence" => 0.8},
                 temporal: %{"choice" => "persistent", "confidence" => 0.9}
               },
               evidence: [
                 %Citation{passage: @u2, verdict: :review, answer: %{"noul" => 0.59}},
                 %Citation{passage: @u3, verdict: :holds, answer: %{"noul" => 0.6}}
               ],
               dropped: [
                 %Citation{passage: @u1, verdict: :dropped, answer: %{"noul" => 0.4}}
               ],
               over_cap: [@u4]
             }
    end

    test "is review when no citation holds", ctx do
      gathered = %Gathered{concern: ctx.cashflow, passages: [@u1]}

      finding =
        Judge.resolve(gathered, descriptors(%{"fit:U1" => %{"noul" => 0.5}}), ctx.policy, @band)

      assert finding.verdict == :review
    end

    test "fails when every passage is dropped", ctx do
      gathered = %Gathered{concern: ctx.cashflow, passages: [@u1]}

      finding =
        Judge.resolve(gathered, descriptors(%{"fit:U1" => %{"noul" => 0.1}}), ctx.policy, @band)

      assert {finding.verdict, finding.evidence} == {:fails, []}
    end
  end

  describe "resolve/4 for a concern built from factors" do
    setup ctx do
      %{
        gathered: %Gathered{
          concern: ctx.household,
          passages: [@u3, @u9],
          roles: %{household: @u3, income: @u9}
        }
      }
    end

    test "holds when every asked check clears high, citing each role's passage", ctx do
      answers =
        descriptors(%{
          "same_household" => %{"noul" => 0.9},
          "concentrated_income" => %{"noul" => 0.8}
        })

      finding = Judge.resolve(ctx.gathered, answers, ctx.policy, @band)

      assert finding == %Finding{
               concern: :household_income,
               category: :resilience,
               verdict: :holds,
               checks: %{
                 same_household: %{"noul" => 0.9},
                 concentrated_income: %{"noul" => 0.8}
               },
               descriptors: %{
                 severity: %{"score" => 1.2, "confidence" => 0.8},
                 temporal: %{"choice" => "persistent", "confidence" => 0.9}
               },
               evidence: [
                 %Citation{passage: @u3, verdict: :holds, answer: nil},
                 %Citation{passage: @u9, verdict: :holds, answer: nil}
               ],
               dropped: [],
               over_cap: []
             }
    end

    test "fails when a check is at or below low", ctx do
      answers =
        descriptors(%{
          "same_household" => %{"noul" => 0.4},
          "concentrated_income" => %{"noul" => 0.9}
        })

      assert Judge.resolve(ctx.gathered, answers, ctx.policy, @band).verdict == :fails
    end

    test "is review when a check sits in the band", ctx do
      answers =
        descriptors(%{
          "same_household" => %{"noul" => 0.5},
          "concentrated_income" => %{"noul" => 0.9}
        })

      assert Judge.resolve(ctx.gathered, answers, ctx.policy, @band).verdict == :review
    end

    test "cites a passage filling two roles once, and records only the checks asked", ctx do
      same = @u3

      gathered = %Gathered{
        concern: ctx.household,
        passages: [same],
        roles: %{household: same, income: same}
      }

      answers = descriptors(%{"concentrated_income" => %{"noul" => 0.9}})

      finding = Judge.resolve(gathered, answers, ctx.policy, @band)

      assert {finding.evidence, finding.checks} ==
               {[%Citation{passage: same, verdict: :holds, answer: nil}],
                %{concentrated_income: %{"noul" => 0.9}}}
    end
  end

  test "a finding encodes with Jason, names and verdicts as strings", ctx do
    gathered = %Gathered{concern: ctx.cashflow, passages: [@u1]}

    finding =
      Judge.resolve(gathered, descriptors(%{"fit:U1" => %{"noul" => 0.9}}), ctx.policy, @band)

    assert Jason.decode!(Jason.encode!(finding)) == %{
             "concern" => "cashflow_stress",
             "category" => "resilience",
             "verdict" => "holds",
             "checks" => %{},
             "descriptors" => %{
               "severity" => %{"score" => 1.2, "confidence" => 0.8},
               "temporal" => %{"choice" => "persistent", "confidence" => 0.9}
             },
             "evidence" => [
               %{
                 "passage" => %{
                   "id" => "U1",
                   "text" => "text of U1",
                   "meta" => %{"speaker" => "B"}
                 },
                 "verdict" => "holds",
                 "answer" => %{"noul" => 0.9}
               }
             ],
             "dropped" => [],
             "over_cap" => []
           }
  end
end
