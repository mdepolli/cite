defmodule Cite.PolicyTest do
  use ExUnit.Case, async: true

  alias Cite.Policy
  alias Cite.Policy.{Build, Check, Concern, Question, Role}
  alias Cite.TestPolicies.{Household, Riddles}

  describe "Build.read/1" do
    test "defaults category to the concern's name, the fit to its indicator, and exclusive to false" do
      riddle = %Question{
        type: :noul,
        text: "Does {passage} pose a riddle?",
        focus: nil,
        criteria: %{
          true: %{what: "A question asked to be puzzled over."},
          false: %{what: "A plain question, a statement, or a remark."}
        }
      }

      assert Build.read(Riddles) == %Policy{
               exclusive: false,
               filters: [],
               factors: [],
               descriptors: [],
               concerns: [
                 %Concern{
                   name: :riddle,
                   category: :riddle,
                   indicator: riddle,
                   fit: riddle,
                   roles: [],
                   checks: []
                 }
               ]
             }
    end

    test "compiles a full policy: filters, both kinds of concern, factors, descriptors" do
      assert Build.read(Household) == %Policy{
               exclusive: true,
               filters: [
                 client_speaking: %Question{
                   type: :noul,
                   text: "Is the speaker of {passage} the client?",
                   focus: nil,
                   criteria: %{
                     true: %{what: "The client speaks about their own life."},
                     false: %{what: "The adviser speaks."}
                   }
                 }
               ],
               concerns: [
                 %Concern{
                   name: :cashflow_stress,
                   category: :resilience,
                   indicator: %Question{
                     type: :noul,
                     text: "Does {passage} say money is short now?",
                     focus: nil,
                     criteria: %{
                       true: %{
                         what: "Money is short now.",
                         examples: ["we're behind on the mortgage"]
                       },
                       false: %{what: "No strain.", not_for: "Bills listed as facts."}
                     }
                   },
                   fit: %Question{
                     type: :noul,
                     text: "Does {passage} evidence that a shock could not be absorbed?",
                     focus: nil,
                     criteria: %{
                       true: %{what: "Costs look unmanageable now."},
                       false: %{what: "Ordinary budget figures."}
                     }
                   },
                   roles: [],
                   checks: []
                 },
                 %Concern{
                   name: :household_income,
                   category: :resilience,
                   indicator: nil,
                   fit: nil,
                   roles: [
                     %Role{
                       name: :household,
                       factor: :dependents,
                       optional: false,
                       distinct: false
                     },
                     %Role{
                       name: :income,
                       factor: :primary_income,
                       optional: false,
                       distinct: false
                     },
                     %Role{
                       name: :other_earner,
                       factor: :other_household_income,
                       optional: true,
                       distinct: true
                     }
                   ],
                   checks: [
                     %Check{
                       name: :same_household,
                       distinct: true,
                       roles: [:household, :income],
                       question: %Question{
                         type: :noul,
                         text: "Do {household} and {income} describe the same household?",
                         focus: nil,
                         criteria: %{
                           true: %{what: "The same household."},
                           false: %{what: "Different people or occasions."}
                         }
                       }
                     },
                     %Check{
                       name: :concentrated_income,
                       distinct: false,
                       roles: [:household, :income],
                       question: %Question{
                         type: :noul,
                         text:
                           "Given {household} and {income}, does one person's pay support the household?",
                         focus: nil,
                         criteria: %{
                           true: %{what: "One main earner."},
                           false: %{what: "Two comparable earners."}
                         }
                       }
                     }
                   ]
                 }
               ],
               factors: [
                 dependents: %Question{
                   type: :noul,
                   text: "Does {passage} mention dependents?",
                   focus: nil,
                   criteria: %{
                     true: %{what: "Mentions dependents."},
                     false: %{what: "No dependents."}
                   }
                 },
                 primary_income: %Question{
                   type: :noul,
                   text: "Does {passage} state a main salary?",
                   focus: nil,
                   criteria: %{true: %{what: "Gives a salary."}, false: %{what: "No salary."}}
                 },
                 other_household_income: %Question{
                   type: :noul,
                   text: "Does {passage} state a partner's income?",
                   focus: nil,
                   criteria: %{
                     true: %{what: "Gives a partner's income."},
                     false: %{what: "No other earner."}
                   }
                 }
               ],
               descriptors: [
                 severity: %Question{
                   type: :score,
                   text: "How much does this affect the speaker?",
                   focus: "Judge the effect, not the topic.",
                   criteria: ["In passing.", "It worries them.", "They cannot manage."]
                 },
                 temporal: %Question{
                   type: :choice,
                   text: "Is it temporary or lasting?",
                   focus: nil,
                   criteria: %{
                     "transient" => "Expected to recover.",
                     "persistent" => "Lasting.",
                     "unknown" => "Not said."
                   }
                 }
               ]
             }
    end

    test "raises on a module that is not a policy" do
      assert_raise ArgumentError, ~r/Enum is not a Cite policy/, fn ->
        Build.read(Enum)
      end
    end
  end

  describe "Build.read/1 check roles" do
    test "include the roles a check's focus names, not only its question" do
      %Policy{concerns: [concern]} = Build.read(Cite.TestPolicies.FocusRole)

      assert Enum.map(concern.checks, &{&1.name, &1.roles}) == [
               same_household: [:household, :income],
               concentrated_income: [:income, :household, :other_earner]
             ]
    end
  end
end
