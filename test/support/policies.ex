defmodule Cite.TestPolicies.Riddles do
  @moduledoc false
  use Cite.Policy

  concern :riddle do
    detect do
      question "Does {passage} pose a riddle?"
      yes "A question asked to be puzzled over."
      no "A plain question, a statement, or a remark."
    end
  end
end

defmodule Cite.TestPolicies.Household do
  @moduledoc false
  use Cite.Policy

  filter :client_speaking do
    question "Is the speaker of {passage} the client?"
    yes "The client speaks about their own life."
    no "The adviser speaks."
  end

  concern :cashflow_stress do
    category :resilience

    detect do
      question "Does {passage} say money is short now?"

      yes do
        what "Money is short now."
        examples ["we're behind on the mortgage"]
      end

      no do
        what "No strain."
        not_for "Bills listed as facts."
      end
    end

    confirm do
      question "Does {passage} evidence that a shock could not be absorbed?"
      yes "Costs look unmanageable now."
      no "Ordinary budget figures."
    end
  end

  concern :household_income do
    category :resilience

    role :household, factor: :dependents
    role :income, factor: :primary_income
    role :other_earner, factor: :other_household_income, optional: true, distinct: true

    check :same_household do
      distinct true
      question "Do {household} and {income} describe the same household?"
      yes "The same household."
      no "Different people or occasions."
    end

    check :concentrated_income do
      question "Given {household} and {income}, does one person's pay support the household?"
      yes "One main earner."
      no "Two comparable earners."
    end
  end

  factor :dependents do
    question "Does {passage} mention dependents?"
    yes "Mentions dependents."
    no "No dependents."
  end

  factor :primary_income do
    question "Does {passage} state a main salary?"
    yes "Gives a salary."
    no "No salary."
  end

  factor :other_household_income do
    question "Does {passage} state a partner's income?"
    yes "Gives a partner's income."
    no "No other earner."
  end

  score :severity do
    question "How much does this affect the speaker?"
    focus "Judge the effect, not the topic."
    levels ["In passing.", "It worries them.", "They cannot manage."]
  end

  choice :temporal do
    question "Is it temporary or lasting?"
    option :transient, "Expected to recover."
    option :persistent, "Lasting."
    option :unknown, "Not said."
  end
end

defmodule Cite.TestPolicies.TwoConcerns do
  @moduledoc false
  use Cite.Policy

  filter :client_speaking do
    question "Is the speaker of {passage} the client?"
    yes "The client speaks."
    no "The adviser speaks."
  end

  concern :health do
    detect do
      question "Does {passage} disclose a health condition?"
      yes "A condition."
      no "No condition."
    end
  end

  concern :life_event do
    detect do
      question "Does {passage} disclose a life event?"
      yes "An event."
      no "No event."
    end
  end
end

defmodule Cite.TestPolicies.SharedFactor do
  @moduledoc false
  use Cite.Policy

  concern :one do
    role :household, factor: :dependents

    check :is_one do
      question "Is {household} the one?"
      yes "y"
      no "n"
    end
  end

  concern :two do
    role :household, factor: :dependents

    check :is_two do
      question "Is {household} the two?"
      yes "y"
      no "n"
    end
  end

  factor :dependents do
    question "Does {passage} mention dependents?"
    yes "Mentions dependents."
    no "No dependents."
  end
end

defmodule Cite.TestPolicies.FocusRole do
  @moduledoc false
  use Cite.Policy

  concern :household_income do
    role :household, factor: :dependents
    role :income, factor: :primary_income
    role :other_earner, factor: :other_household_income, optional: true, distinct: true

    check :same_household do
      question "Do {household} and {income} describe the same household?"
      yes "The same household."
      no "Different people."
    end

    check :concentrated_income do
      question "Does one person's pay in {income} support {household}?"
      focus "Weigh {other_earner} against it."
      yes "One main earner."
      no "Two comparable earners."
    end
  end

  factor :dependents do
    question "Does {passage} mention dependents?"
    yes "Mentions dependents."
    no "No dependents."
  end

  factor :primary_income do
    question "Does {passage} state a main salary?"
    yes "Gives a salary."
    no "No salary."
  end

  factor :other_household_income do
    question "Does {passage} state a partner's income?"
    yes "Gives a partner's income."
    no "No other earner."
  end
end
