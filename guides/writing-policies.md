# Writing policies

A policy is what the source is judged against: the caller's own rules for
what counts. It is declared once, in a module, and checked when the module
compiles.

```elixir
defmodule Vuln.Policy do
  use Cite.Policy

  exclusive true

  filter :client_speaking do ... end
  concern :cashflow_stress do ... end
  concern :household_income do ... end
  factor :dependents do ... end
  score :severity do ... end
  choice :temporal do ... end
end
```

## Vocabulary

- **Indicator**: a yes/no question asked of every passage in round 1. It
  comes in three kinds:
  - **Filter**: never a finding; decides which passages count at all.
  - **Concern**: something a finding can be. Screened directly with its own
    indicator, or built from factors.
  - **Factor**: never a finding alone; fills a role in a concern built from
    factors.
- **Fit**: a directly screened concern's second question, asked in round 2
  of each passage it matched, with its siblings. It decides which passages
  are cited.
- **Check**: a question across a concern's roles, asked in round 2. It
  decides whether the finding holds.
- **Category**: what a concern is reported as.
- **Descriptor**: a Score or Choice asked of every finding. It describes and
  never decides.
- **Evidence**: the passages a finding cites.

## Questions

Every yes/no question — a filter, factor, indicator, fit, or check — has the
same body:

```elixir
question "Does {passage} say the speaker's household is currently struggling with money?"
focus "Judge present strain, not past hardship."   # optional
yes "The speaker says money is short now."
no "Costs are mentioned without strain."
```

`yes` and `no` take a string, or a block with the structured criteria
TypeSafe documents:

```elixir
yes do
  what "The speaker says money is short now: ..."
  not_for "A mortgage or bills listed as facts; ..."   # optional
  examples ["we're behind on the mortgage"]            # optional
end
```

On the wire they are the Noul's `"true"` and `"false"` criteria; the DSL
says `yes`/`no` because `true` and `false` are Elixir literals.

## Filters

```elixir
filter :client_speaking do
  question "Is the speaker of {passage} the client or the client's partner, disclosing their own circumstances?"
  yes "A client speaks in their own voice about their own life, money, or household."
  no "The adviser speaks, or the subject is a third party or a hypothetical."
end
```

A passage is evidence for any concern or factor only if it matches every
filter. A policy may have none.

## Concerns screened directly

```elixir
concern :cashflow_stress do
  category :resilience

  indicator do
    question "Does {passage} say the speaker's household is currently struggling with money?"
    yes "..."
    no "..."
  end

  fit do
    question "Does {passage} evidence that the speaker's household cannot absorb a financial shock now?"
    yes "..."
    no "..."
  end
end
```

The indicator casts the net in round 1; the fit decides, in round 2, which
matched passages are cited. `fit` is optional: without it the indicator is
asked again, over the concern's gathered passages instead of a screening
window. `category` defaults to the concern's name.

## Concerns built from factors

```elixir
concern :household_income do
  category :resilience

  role :household, factor: :dependents
  role :income, factor: :primary_income
  role :other_earner, factor: :other_household_income, optional: true, distinct: true

  check :same_household do
    distinct true
    question "Do {household} and {income} describe the same household?"
    yes "Both statements are about the same family or household."
    no "They are about different people or occasions."
  end

  check :concentrated_income do
    question "Given {household} and {income}, does one person's pay support a household with dependents?"
    yes "..."
    no "..."
  end
end
```

- Each role names a factor the policy declares, and is filled by that
  factor's strongest match. `optional: true` lets the finding stand without
  it; `distinct: true` requires a passage no other role holds.
- A check is asked only when every role it names, in its question or its
  focus, is filled. `distinct true`
  also requires those roles to be different passages: a line cannot
  corroborate itself. It sits inside the block because a Spark entity takes
  options or a `do` block, not both.
- At least one check must name only required roles and not be distinct, so
  every finding is judged by something.

## Factors

```elixir
factor :dependents do
  question "Does {passage} mention children, dependents, or household size?"
  yes "States children, dependents, or how many people are in the household."
  no "No household size or dependents."
end
```

One factor can fill roles in several concerns; it is screened once.

## Descriptors

```elixir
score :severity do
  question "How much does the circumstance affect the speaker's ability to manage this financial matter?"
  levels ["Mentioned in passing.", "It worries them.", "They cannot manage it themselves."]
end

choice :temporal do
  question "Is the circumstance temporary or lasting?"
  option :transient, "A recent event expected to recover from"
  option :persistent, "A lasting condition or permanent change"
  option :unknown, "The statements do not say"
end
```

Every finding is described by every descriptor, asked over all of its
evidence. A Score has 2 to 10 unique levels; a Choice at least one option.

## Exclusive

`exclusive true` makes a passage evidence for at most one directly screened
concern: the one whose indicator scored it highest, the concern declared
first winning a tie. The choice is final; a passage its winning concern's fit
drops is not reconsidered elsewhere. Without it, a passage is evidence for
every concern it matches. Concerns built from factors are unaffected.

## Placeholders

Questions name what they read, and Cite writes the backticked path.

- `{passage}` is the passage an indicator or fit is asked about; `{household}`
  names a role. A placeholder means the passage's text.
- Placeholders expand in `question` and `focus`, not in criteria.
- Filters, factors, indicators, and fits use `{passage}` and nothing else. A
  check uses at least one of its concern's roles and nothing else.
  Descriptors use none: they read all of the finding's evidence.
- One placeholder becomes the question's `inspect`; several become
  `compare`, TypeSafe's field for "a list of things to check or to compare".
- Any `{word}` is a placeholder, so a question cannot contain literal braces
  around a word.

## Compile-time checks

A policy fails to compile, pointing at the declaration, on:

- a policy with no concern;
- two indicators, or two descriptors, with one name, or a name containing `:`;
- a check and a descriptor with one name;
- two roles, or two checks, with one name in the same concern;
- a concern with both an indicator and roles, or neither;
- a fit on a concern built from roles, or checks on a concern screened
  directly: either would compile and never be asked;
- a role naming an undeclared factor, a role named `:passage`, or a role
  name that is not a word of letters, digits, and `_` (it is a placeholder
  and part of a path);
- a concern built from factors with no always-asked check, or a distinct
  check naming fewer than two roles;
- a Score outside 2 to 10 unique levels, or a Choice without unique options;
- a missing `question`, `levels`, `yes`, or `no`;
- any placeholder rule above.

## Wording that holds up

The model reads literally. These are the rules that held up in practice.

**One proposition per question.** "Does it pose a riddle *and* is it
unanswered" is two questions, and the model answers whichever it weighs
more. Ask the first as an indicator and the second as the fit.

**Boundary cases go in `not_for`.** The first wording of a question is the
half of the instruction you thought of; the wrong answers you meet afterwards
are the other half. Put them in the criteria as paraphrases, not as fixture
lines. When you find yourself explaining what you really meant, that
explanation is the missing `not_for`.

**Question and criteria agree.** When they disagree, the model answers the
question and ignores the criteria.

**Make every Score level reachable.** A level no passage could earn flattens
the model's confidence on the others.

**Show the model only what it needs.** `show:` on the source decides which
meta the model reads. Timestamps beside utterances read as "different
occasions" and sank a same-household check; keep them in `meta`, unshown.

**Pin the wording.** Once the questions work, they are part of your
benchmark. A model's reading of the same wording shifts between versions, so
a change of model is a change of questions until you have measured
otherwise.
