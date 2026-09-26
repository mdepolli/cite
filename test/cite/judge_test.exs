defmodule Cite.JudgeTest do
  use ExUnit.Case, async: true

  alias Cite.{Citation, Error, Finding, Gathered, Judge, Passage, Source}
  alias Cite.{TestRun, TestTerms}
  alias Cite.Wire.Object

  @band {0.4, 0.6}

  setup do
    terms = TestTerms.household()
    [cashflow, household] = terms.concerns
    source = Source.new([], as: "utterances", show: [:speaker])

    %{
      run: TestRun.new(terms, source: source, review_band: @band),
      source: source,
      cashflow: cashflow,
      household: household
    }
  end

  @u1 %Passage{id: "U1", text: "text of U1", meta: %{speaker: "B"}}
  @u2 %Passage{id: "U2", text: "text of U2", meta: %{speaker: "B"}}
  @u3 %Passage{id: "U3", text: "text of U3", meta: %{speaker: "B"}}
  @u4 %Passage{id: "U4", text: "text of U4", meta: %{speaker: "B"}}
  @u9 %Passage{id: "U9", text: "text of U9", meta: %{speaker: "B"}}

  # Judges one gathered finding from one successful reply.
  defp judged(run, gathered, answers) do
    %{findings: [finding]} =
      Judge.resolve(run, [{gathered, {:ok, %{answers: answers, usage: nil}}}])

    finding
  end

  # The model's descriptor answers, with the confirms or checks each test adds.
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

  defp confirm_u1 do
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

  defp confirm_u2 do
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

  describe "request/2 for a directly screened concern" do
    test "asks the confirm of each passage among its siblings, and the descriptors over all",
         ctx do
      # Arrange
      gathered = %Gathered{concern: ctx.cashflow, passages: [@u1, @u2]}

      # Act
      request = Judge.request(ctx.run, gathered)

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
                 "confirm:U1" => confirm_u1(),
                 "confirm:U2" => confirm_u2(),
                 "severity" => severity_over_u1_u2(),
                 "temporal" => temporal_over_u1_u2()
               }
             }
    end
  end

  describe "request/2 for a concern built from factors" do
    test "puts each role at the top level and asks the checks that apply", ctx do
      # Arrange
      gathered = %Gathered{
        concern: ctx.household,
        passages: [@u3, @u9],
        roles: %{household: @u3, income: @u9}
      }

      # Act
      request = Judge.request(ctx.run, gathered)

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

    test "compares every filled role in the descriptors, the optional one included", ctx do
      # Arrange
      gathered = %Gathered{
        concern: ctx.household,
        passages: [@u3, @u4, @u9],
        roles: %{household: @u3, income: @u9, other_earner: @u4}
      }

      # Act
      %{"state" => state, "questions" => questions} =
        Judge.request(ctx.run, gathered)

      # Assert
      assert Enum.sort(Map.keys(state)) == ["household", "income", "other_earner"]

      assert questions["severity"]["instructions"]["compare"] ==
               ["`household.text`", "`income.text`", "`other_earner.text`"]
    end

    test "skips a distinct check when its roles resolve to one passage", ctx do
      # Arrange
      same = @u3

      gathered = %Gathered{
        concern: ctx.household,
        passages: [same],
        roles: %{household: same, income: same}
      }

      # Act
      %{"questions" => questions} = Judge.request(ctx.run, gathered)

      # Assert
      assert Enum.sort(Map.keys(questions)) == ["concentrated_income", "severity", "temporal"]
    end
  end

  describe "request/2 with a role named only in a check's focus" do
    test "skips that check while the role is empty, instead of failing to expand the focus",
         ctx do
      # Arrange
      terms = TestTerms.focus_role()
      [household] = terms.concerns

      gathered = %Gathered{
        concern: household,
        passages: [@u3, @u9],
        roles: %{household: @u3, income: @u9}
      }

      # Act
      %{"questions" => questions} =
        Judge.request(TestRun.new(terms, source: ctx.source), gathered)

      # Assert
      assert Map.keys(questions) == ["same_household"]
    end

    test "once the role is filled, reads it beside the roles the question names", ctx do
      # Arrange
      terms = TestTerms.focus_role()
      [household] = terms.concerns

      gathered = %Gathered{
        concern: household,
        passages: [@u3, @u4, @u9],
        roles: %{household: @u3, income: @u9, other_earner: @u4}
      }

      # Act
      %{"questions" => questions} =
        Judge.request(TestRun.new(terms, source: ctx.source), gathered)

      # Assert
      assert questions["concentrated_income"]["instructions"] == %{
               "question" => "Does one person's pay in `income.text` support `household.text`?",
               "focus" => "Weigh `other_earner.text` against it.",
               "compare" => ["`income.text`", "`household.text`", "`other_earner.text`"]
             }
    end
  end

  describe "resolve/2 folding replies into the run" do
    test "folds findings, an error per failed request, and each reply's usage and model", ctx do
      # Arrange
      held = %Gathered{concern: ctx.cashflow, passages: [@u1]}

      failed = %Gathered{
        concern: ctx.household,
        passages: [@u3, @u9],
        roles: %{household: @u3, income: @u9}
      }

      outcomes = [
        {held,
         {:ok,
          %{
            answers: descriptors(%{"confirm:U1" => %{"noul" => 0.9}}),
            usage: %{input_tokens: 40, output_tokens: 0},
            model: "jev-1.13.0"
          }}},
        {failed, {:error, :request_too_large}}
      ]

      # Act
      run = Judge.resolve(ctx.run, outcomes)

      # Assert
      assert %{findings: run.findings, errors: run.errors, usages: run.usages, models: run.models} ==
               %{
                 findings: [
                   %Finding{
                     concern: :cashflow_stress,
                     category: :resilience,
                     verdict: :holds,
                     checks: %{},
                     descriptors: %{
                       severity: %{"score" => 1.2, "confidence" => 0.8},
                       temporal: %{"choice" => "persistent", "confidence" => 0.9}
                     },
                     evidence: [
                       %Citation{passage: @u1, verdict: :holds, answer: %{"noul" => 0.9}}
                     ],
                     dropped: [],
                     over_cap: []
                   }
                 ],
                 errors: [
                   %Error{
                     concern: :household_income,
                     passage_ids: ["U3", "U9"],
                     reason: :request_too_large
                   }
                 ],
                 usages: [%{input_tokens: 40, output_tokens: 0}],
                 models: ["jev-1.13.0"]
               }
    end

    test "adds its errors, usages, and models to those round 1 left", ctx do
      # Arrange
      earlier = %Error{concern: nil, passage_ids: ["U0"], reason: :timeout}
      run = %{ctx.run | errors: [earlier], usages: [nil], models: ["jev-1.12.0"]}
      held = %Gathered{concern: ctx.cashflow, passages: [@u1]}
      failed = %Gathered{concern: ctx.cashflow, passages: [@u2]}

      reply = %{
        answers: descriptors(%{"confirm:U1" => %{"noul" => 0.9}}),
        usage: nil,
        model: "jev-1.13.0"
      }

      # Act
      run = Judge.resolve(run, [{held, {:ok, reply}}, {failed, {:error, :timeout}}])

      # Assert
      assert {run.errors, run.usages, run.models} ==
               {[
                  earlier,
                  %Error{concern: :cashflow_stress, passage_ids: ["U2"], reason: :timeout}
                ], [nil, nil], ["jev-1.12.0", "jev-1.13.0"]}
    end

    test "judges no findings and adds nothing when nothing was gathered", ctx do
      # Act
      run = Judge.resolve(ctx.run, [])

      # Assert
      assert {run.findings, run.errors, run.usages, run.models} == {[], [], [], []}
    end
  end

  describe "resolve/2 for a directly screened concern" do
    test "drops, reviews, and holds each passage by its confirm", ctx do
      # Arrange
      gathered = %Gathered{
        concern: ctx.cashflow,
        passages: [@u1, @u2, @u3],
        over_cap: [@u4]
      }

      answers =
        descriptors(%{
          "confirm:U1" => %{"noul" => 0.4},
          "confirm:U2" => %{"noul" => 0.59},
          "confirm:U3" => %{"noul" => 0.6}
        })

      # Act
      finding = judged(ctx.run, gathered, answers)

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
      # Arrange
      gathered = %Gathered{concern: ctx.cashflow, passages: [@u1]}
      answers = descriptors(%{"confirm:U1" => %{"noul" => 0.5}})

      # Act + Assert
      assert judged(ctx.run, gathered, answers).verdict == :review
    end

    test "fails when every passage is dropped", ctx do
      # Arrange
      gathered = %Gathered{concern: ctx.cashflow, passages: [@u1]}
      answers = descriptors(%{"confirm:U1" => %{"noul" => 0.1}})

      # Act
      finding = judged(ctx.run, gathered, answers)

      # Assert
      assert {finding.verdict, finding.evidence} == {:fails, []}
    end
  end

  describe "resolve/2 for a concern built from factors" do
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
      # Arrange
      answers =
        descriptors(%{
          "same_household" => %{"noul" => 0.9},
          "concentrated_income" => %{"noul" => 0.8}
        })

      # Act
      finding = judged(ctx.run, ctx.gathered, answers)

      # Assert
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
      # Arrange
      answers =
        descriptors(%{
          "same_household" => %{"noul" => 0.4},
          "concentrated_income" => %{"noul" => 0.9}
        })

      # Act + Assert
      assert judged(ctx.run, ctx.gathered, answers).verdict == :fails
    end

    test "holds when a check sits exactly at high", ctx do
      # Arrange
      answers =
        descriptors(%{
          "same_household" => %{"noul" => 0.6},
          "concentrated_income" => %{"noul" => 0.9}
        })

      # Act + Assert
      assert judged(ctx.run, ctx.gathered, answers).verdict == :holds
    end

    test "is review when a check sits in the band", ctx do
      # Arrange
      answers =
        descriptors(%{
          "same_household" => %{"noul" => 0.5},
          "concentrated_income" => %{"noul" => 0.9}
        })

      # Act + Assert
      assert judged(ctx.run, ctx.gathered, answers).verdict == :review
    end

    test "cites a passage filling two roles once, and records only the checks asked", ctx do
      # Arrange
      same = @u3

      gathered = %Gathered{
        concern: ctx.household,
        passages: [same],
        roles: %{household: same, income: same}
      }

      answers = descriptors(%{"concentrated_income" => %{"noul" => 0.9}})

      # Act
      finding = judged(ctx.run, gathered, answers)

      # Assert
      assert {finding.evidence, finding.checks} ==
               {[%Citation{passage: same, verdict: :holds, answer: nil}],
                %{concentrated_income: %{"noul" => 0.9}}}
    end
  end

  test "a finding encodes with Jason, names and verdicts as strings", ctx do
    # Arrange
    gathered = %Gathered{concern: ctx.cashflow, passages: [@u1]}
    finding = judged(ctx.run, gathered, descriptors(%{"confirm:U1" => %{"noul" => 0.9}}))

    # Act + Assert
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
