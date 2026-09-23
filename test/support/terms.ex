defmodule Cite.TestTerms do
  @moduledoc false
  # The terms each test policy in `Cite.TestPolicies` compiles to, written out.
  # The core tests (Screen, Gather, Judge) read these, so a DSL regression
  # fails `Cite.PolicyTest`, which pins each one to its policy, and nothing else.

  alias Cite.Policy.{Check, Concern, Question, Role, Terms}

  def riddles do
    %Terms{
      exclusive: false,
      filters: [],
      factors: [],
      descriptors: [],
      concerns: [
        %Concern{
          name: :riddle,
          category: :riddle,
          detect: %Question{
            type: :noul,
            text: "Does {passage} pose a riddle?",
            focus: nil,
            criteria: %{
              true: %{what: "A question asked to be puzzled over."},
              false: %{what: "A plain question, a statement, or a remark."}
            }
          },
          confirm: %Question{
            type: :noul,
            text: "Does {passage} pose a riddle?",
            focus: nil,
            criteria: %{
              true: %{what: "A question asked to be puzzled over."},
              false: %{what: "A plain question, a statement, or a remark."}
            }
          },
          roles: [],
          checks: []
        }
      ]
    }
  end

  def household do
    %Terms{
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
          detect: %Question{
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
          confirm: %Question{
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
          detect: nil,
          confirm: nil,
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

  def two_concerns do
    %Terms{
      exclusive: true,
      filters: [
        client_speaking: %Question{
          type: :noul,
          text: "Is the speaker of {passage} the client?",
          focus: nil,
          criteria: %{true: %{what: "The client speaks."}, false: %{what: "The adviser speaks."}}
        }
      ],
      concerns: [
        %Concern{
          name: :health,
          category: :health,
          detect: %Question{
            type: :noul,
            text: "Does {passage} disclose a health condition?",
            focus: nil,
            criteria: %{true: %{what: "A condition."}, false: %{what: "No condition."}}
          },
          confirm: %Question{
            type: :noul,
            text: "Does {passage} disclose a health condition?",
            focus: nil,
            criteria: %{true: %{what: "A condition."}, false: %{what: "No condition."}}
          },
          roles: [],
          checks: []
        },
        %Concern{
          name: :life_event,
          category: :life_event,
          detect: %Question{
            type: :noul,
            text: "Does {passage} disclose a life event?",
            focus: nil,
            criteria: %{true: %{what: "An event."}, false: %{what: "No event."}}
          },
          confirm: %Question{
            type: :noul,
            text: "Does {passage} disclose a life event?",
            focus: nil,
            criteria: %{true: %{what: "An event."}, false: %{what: "No event."}}
          },
          roles: [],
          checks: []
        }
      ],
      factors: [],
      descriptors: []
    }
  end

  def focus_role do
    %Terms{
      exclusive: false,
      filters: [],
      concerns: [
        %Concern{
          name: :household_income,
          category: :household_income,
          detect: nil,
          confirm: nil,
          roles: [
            %Role{name: :household, factor: :dependents, optional: false, distinct: false},
            %Role{name: :income, factor: :primary_income, optional: false, distinct: false},
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
              distinct: false,
              roles: [:household, :income],
              question: %Question{
                type: :noul,
                text: "Do {household} and {income} describe the same household?",
                focus: nil,
                criteria: %{
                  true: %{what: "The same household."},
                  false: %{what: "Different people."}
                }
              }
            },
            %Check{
              name: :concentrated_income,
              distinct: false,
              roles: [:income, :household, :other_earner],
              question: %Question{
                type: :noul,
                text: "Does one person's pay in {income} support {household}?",
                focus: "Weigh {other_earner} against it.",
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
          criteria: %{true: %{what: "Mentions dependents."}, false: %{what: "No dependents."}}
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
      descriptors: []
    }
  end
end
