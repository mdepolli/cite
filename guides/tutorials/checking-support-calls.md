# Checking support calls against procedure

This guide builds a policy that reads a support conversation and checks it
against your written procedure: did the agent verify the customer before
changing anything, offer the refund, update the account? Each step comes
back with the agent's turns that show it, so a QA reviewer can coach from
the call itself instead of a score.

It assumes you know your contact centre's procedures and have not used
Cite before. The conversation lines below are invented.

## What you will build

A policy module, the code that runs it on one conversation, and a
checklist like this:

| Step | Turns |
|---|---|
| identity verified | t5: "Thanks Dana. Can I also get the email and the order ID?" |
| refund offered | t7: "I've issued a refund of $42 to your card." |
| account updated | not found |
| order updated | not found |

A person reading that checklist sees at once what the agent did, and what
to look for in the rest of the call.

You write down what counts as each step, split the call into turns, build
the checklist from the findings, and check the order of steps. Cite asks
your questions of every turn and cites the ones that fit.

## 1. Decide what counts as each step

Take the steps from your written procedure, and for each one write down
what the agent says when they do it, and what sounds like it and is not.

- **Verifying identity** is asking for, or confirming, the details used to
  check who the customer is: an email and order ID, a zip code, a PIN or a
  security answer. Agents often ask for them one at a time. Asking for the
  name alone, to look the account up, is not verification. This is the
  boundary that matters most: every call starts with a lookup.
- **Offering a refund** is offering money back or confirming one. Explaining
  the refund policy, or a discount on the next order, is not.
- **Updating the account** (name, address, payment method, subscription)
  and **updating an order** (shipping, items, address, cancelling) are
  separate steps. Asking for the new address is not the change; saying it
  has been changed is.
- **A step can be a short confirmation.** "All done" or "let me process
  that", right after the agent took the new address, is the account
  update. Count it when the turns before make clear which step it is.

Some steps leave no trace in the conversation. An agent may change an
order's shipping in the back office and say nothing that ties to it. Cite
reads what was said, so it cannot find those. Check the steps your agents
do silently against your system's own records instead.

## 2. Turn a conversation into a source

One conversation is one source, and one turn is one passage, with the
speaker in `meta`:

```elixir
turns = [
  %{id: "t1", text: "Hi, thanks for contacting us. How can I help?", meta: %{speaker: "agent"}},
  %{id: "t2", text: "My order arrived damaged and I'd like my money back.", meta: %{speaker: "customer"}},
  %{id: "t3", text: "Sorry to hear that. Can I have your full name?", meta: %{speaker: "agent"}},
  %{id: "t4", text: "Dana Whitfield.", meta: %{speaker: "customer"}},
  %{id: "t5", text: "Thanks Dana. Can I also get the email and the order ID?", meta: %{speaker: "agent"}},
  %{id: "t6", text: "dana.w@example.com, and it's 55120.", meta: %{speaker: "customer"}},
  %{id: "t7", text: "I've issued a refund of $42 to your card.", meta: %{speaker: "agent"}}
]

source = Cite.source(turns, as: "turns", show: [:speaker])
```

- **Show the speaker.** A step is something the agent does, and the model
  can only tell who spoke if it sees the field.
- **Leave your system's action log out.** If your transcripts include rows
  such as "refund issued", drop them: they would answer the question for
  the model, and the point is to check what was said.
- **Ids that keep the order,** such as `t1`, `t2`: you will use them to
  check the order of steps.

## 3. Only the agent's turns count

A customer saying "I already gave you my email" is not the agent verifying
anything. A filter sets the customer's turns aside once, for every
concern:

```elixir
filter :agent_speaking do
  question "Is {passage} spoken by the support agent, rather than the customer?"
  yes "The speaker is the agent: the person handling the customer's request."
  no "The speaker is the customer."
end
```

With the speaker shown, this is an easy question, and a cheap one: one
answer per turn. On real support conversations it sorted every turn
correctly.

The speaker is already in `meta`, so why ask the model? Because the
customer's turns must stay in the source. They are what the agent's turns
are read beside in round 1. Cite has no way to mark a passage as context
only, so the filter keeps those turns from being cited instead.

## 4. Write one concern per step

Each step is a concern with a detect: a yes/no question asked of every
agent turn. Word it as your QA reviewers would, not after the button names
in your system.

Verification is the step with the hard boundary, so its `no` names the
lookup explicitly:

```elixir
concern :identity_verified do
  detect do
    question "Does {passage} show the agent checking who the customer is before acting on the account or order: asking for, or confirming, the details used to verify identity?"
    yes "The agent asks for or confirms identifying details to verify the customer or validate a purchase: full name with account ID, order ID, or zip code; username, email address, and order ID; a PIN or security answer; or says the identity or purchase has been verified."
    no "Any other turn, including greeting the customer, or asking about the problem itself. A turn that asks for the customer's name alone ('may I have your full name?') only looks the account up and is no, however it is worded."
  end
end
```

A few rules from practice:

- **Name the exception, not a rule of thumb.** A first wording regularly
  cited "Can I have your full name?" as verification. Rewording it to ask
  for "several details together" kept the lookup out and lost most real
  verifications, because agents ask for details one at a time. Naming the
  lookup itself in the `no` kept both right.
- **Say when a confirmation counts.** The three steps that change
  something say that a turn which only reports it done counts, when the
  turns before make clear which step it is. Short confirmations are still
  the weakest point. Round 1 reads each turn beside the turns around it.
  Round 2 reads only the turns gathered for the step, so the question that
  came before "all done" is gone. Expect such turns to drop or land in
  review.
- **Keep neighbouring steps apart.** The account step's `no` names the
  order step and the order step's names the account, since "change the
  address" can mean either.
- **Ask whether the agent does it, not whether it is discussed.** "Asking
  for the new details without saying they will be changed" is a `no`: the
  step is the change.

The full policy is at the end of this guide. More on the language in
[Writing policies](../writing-policies.md).

## 5. Run it

```elixir
client = Cite.client(Cite.Provider.TypeSafe, api_key: System.fetch_env!("JEV_API_KEY"))
report = Cite.judge(client, source, MyApp.Procedure)
```

A 30-turn conversation is one screening request, which asks the filter and
all four steps of every turn, then one judging request per step found.

## 6. From findings to a checklist

Each finding is one step, citing the agent's turns that show it:

```elixir
defmodule MyApp.Checklist do
  alias Cite.{Citation, Finding, Passage, Report}

  @steps [:identity_verified, :refund_offered, :account_updated, :order_updated]

  # Each step with the ids of the turns that show it, [] when none was
  # found; :unchecked when a request failed.
  def steps(%Report{errors: [_ | _]}), do: :unchecked

  def steps(%Report{findings: findings}) do
    turns =
      for %Finding{concern: step, evidence: evidence} <- findings, into: %{} do
        {step, for(%Citation{passage: %Passage{id: id}} <- evidence, do: id)}
      end

    Map.new(@steps, &{&1, Map.get(turns, &1, [])})
  end
end
```

- **"Not found" is not "not done".** A step the agent performed without
  saying so will show as not found. Before flagging a call, check that step
  against your system's records.
- **A failed request means the call was not checked.** Its turns land in
  `report.errors`; show the call as unchecked and retry it.
- **Review goes to a person.** A `:review` citation is one the model was
  unsure of; put it in front of the reviewer with the turns around it.

### Checking the order of steps

Cite judges turns, not sequences, so "verified identity before issuing the
refund" is a check in your code. The cited turn ids give you the order:

```elixir
defmodule MyApp.Order do
  # Whether the first verification turn comes before the first refund turn,
  # given turn ids in conversation order.
  def verified_first?(%{identity_verified: [first_check | _], refund_offered: [first_refund | _]}, order) do
    Enum.find_index(order, &(&1 == first_check)) < Enum.find_index(order, &(&1 == first_refund))
  end

  def verified_first?(%{refund_offered: []}, _order), do: true
  def verified_first?(_steps, _order), do: false
end
```

Pass it the checklist and the conversation's turn ids in order
(`Enum.map(turns, & &1.id)`). A refund with no verification cited at all
comes back `false`, which is the case you most want to see. Call it only
on a checked call. Given `:unchecked`, it also returns `false`, and an
unchecked call is not a breach.

## 7. Check it against your records

Your system's action log says which steps happened in each conversation.
Compare Cite's checklist with it, call by call. Expect a gap wherever
agents do a step silently, and measure that gap separately: have a careful
reader mark, blind to the log, which steps are visible in the text. Score
Cite against what the text can show, and report the silent steps apart.

Score a keyword list beside the policy too ("refund", "I've updated",
"verify"). On the benchmark behind this guide, keywords were close to the
policy on identity checks and refunds, and far behind on account and order
changes, which agents phrase in many ways. That tells you where the
policy earns its cost.

Keep some conversations aside that you never read while rewording.
[Tuning against labels](../writing-policies.md#tuning-against-labels) has
the method.

## 8. When not to use Cite

If your agents work from scripts and say the same sentence for each step,
a keyword list finds most steps and costs nothing. If your system logs
every action, the log is the record of what happened, and the text adds
little for steps the log already covers.

Cite earns its place where the words matter: steps agents phrase their own
way, what a customer was told rather than what a button did, and calls
from channels your system does not log.

## The whole policy

```elixir
defmodule MyApp.Procedure do
  use Cite.Policy

  filter :agent_speaking do
    question "Is {passage} spoken by the support agent, rather than the customer?"
    yes "The speaker is the agent: the person handling the customer's request."
    no "The speaker is the customer."
  end

  concern :identity_verified do
    detect do
      question "Does {passage} show the agent checking who the customer is before acting on the account or order: asking for, or confirming, the details used to verify identity?"
      yes "The agent asks for or confirms identifying details to verify the customer or validate a purchase: full name with account ID, order ID, or zip code; username, email address, and order ID; a PIN or security answer; or says the identity or purchase has been verified."
      no "Any other turn, including greeting the customer, or asking about the problem itself. A turn that asks for the customer's name alone ('may I have your full name?') only looks the account up and is no, however it is worded."
    end
  end

  concern :refund_offered do
    detect do
      question "Does {passage} show the agent offering, issuing, or confirming a refund to the customer?"
      yes "The agent offers money back, says a refund has been issued or will be, or confirms its amount or method (credit card, gift card, paper check, account credit). So does a turn that only says the step is being done or is done, when the conversation just before makes clear which step it is ('let me process that', 'all done', 'you're all set')."
      no "Any other turn, including asking why the customer wants a refund, explaining the refund policy without offering one, or a promo code or discount on a future purchase."
    end
  end

  concern :account_updated do
    detect do
      question "Does {passage} show the agent changing the customer's account: its name, address, phone number, payment method, or subscription?"
      yes "The agent says they are changing or have changed an account detail: the name, the address on file, the phone number, the payment method, or the subscription (an extension, a bill paid, a service added or removed). So does a turn that only says the step is being done or is done, when the conversation just before makes clear which step it is ('let me process that', 'all done', 'you're all set')."
      no "Any other turn, including asking for the new details without saying they will be changed, or changing an order rather than the account."
    end
  end

  concern :order_updated do
    detect do
      question "Does {passage} show the agent changing an existing order: its shipping, items, address, or status, including cancelling it?"
      yes "The agent says they are changing or have changed an order: upgrading or downgrading its shipping, changing its address or items, or cancelling it. So does a turn that only says the step is being done or is done, when the conversation just before makes clear which step it is ('let me process that', 'all done', 'you're all set')."
      no "Any other turn, including checking an order's status without changing it, placing a new order, or changing the account rather than an order."
    end
  end
end
```
