# How judging works

What happens between `Cite.judge/4` and the report, with the requests the
client receives at each step.

```mermaid
flowchart LR
    A[Screen] --> B[Gather]
    B --> C[Judge]
    C --> D[Report]
```

| Step | Module | What it does |
| ---- | ------ | ------------ |
| Screen | `Cite.Screen` | every detect of every passage, a window per request |
| Gather | `Cite.Gather` | fixed rules turn matches into findings; no model call |
| Judge | `Cite.Judge` | one request per finding, on its own evidence |

`Cite.judge/4` is the shell: it validates the options into a `Cite.Run`,
calls the client, halves an oversized window, and assembles the
`Cite.Report`. Every decision lives in the three pure modules, which never
see the client.

## Round 1: screen

Every detect — filters, directly screened concerns, factors — is asked of
every passage, `window` passages per request. The window sits under the
source's `as`, keyed by id, in source order:

```json
{
  "state": {
    "utterances": {
      "U014": {"id": "U014", "speaker": "B", "text": "we're behind on the mortgage"},
      "U015": {"id": "U015", "speaker": "A", "text": "Let's look at the cashflow chart."}
    }
  },
  "questions": {
    "U014:cashflow_stress": {
      "type": "noul",
      "instructions": {
        "question": "Does `utterances.U014.text` say the speaker's household is currently struggling with money?",
        "inspect": "`utterances.U014.text`"
      },
      "criteria": {"true": {"what": "..."}, "false": {"what": "...", "not_for": "..."}}
    }
  }
}
```

Question keys are `"<passage id>:<detect>"`. A score above `threshold` is
a match. A match decides what is gathered, and so what every confirm
reads: `threshold` changes verdicts, not only recall (see How a finding is
read).

A request the provider refuses as `:request_too_large` is halved and both
halves sent. Only a lone passage over the cap becomes an error; its
siblings are still screened.

## Between rounds: gather

Fixed rules, no model call:

- A passage that fails any filter is set aside. So is a passage whose window
  failed: it has no scores.
- A directly screened concern gathers every remaining match into one
  finding, however many. A passage that matches several concerns is
  evidence for each.
- A concern built from factors fills each role with its strongest match. A
  distinct role takes the strongest match no other role holds. A required
  role left empty means no finding.

## Round 2: judge

One request per finding.

A directly screened concern puts its passages under `as`, so siblings give
each other context. Confirms are keyed `confirm:<passage id>`; descriptors compare
every passage:

```json
{
  "state": {
    "utterances": {
      "U014": {"id": "U014", "speaker": "B", "text": "we're behind on the mortgage"},
      "U031": {"id": "U031", "speaker": "B", "text": "by the end of the month there's nothing left"}
    }
  },
  "questions": {
    "confirm:U014": {"type": "noul", "instructions": {"question": "Does `utterances.U014.text` evidence ...", "inspect": "`utterances.U014.text`"}, "criteria": {"...": "..."}},
    "confirm:U031": {"type": "noul", "instructions": {"question": "Does `utterances.U031.text` evidence ...", "inspect": "`utterances.U031.text`"}, "criteria": {"...": "..."}},
    "severity": {"type": "score", "instructions": {"question": "...", "compare": ["`utterances.U014.text`", "`utterances.U031.text`"]}, "criteria": ["...", "...", "..."]}
  }
}
```

A concern built from factors puts each role at the top level and asks the
checks that apply:

```json
{
  "state": {
    "household": {"id": "U003", "speaker": "B", "text": "we've got two kids at home"},
    "income": {"id": "U009", "speaker": "B", "text": "I'm on about sixty a year"}
  },
  "questions": {
    "same_household": {
      "type": "noul",
      "instructions": {
        "question": "Do `household.text` and `income.text` describe the same household?",
        "compare": ["`household.text`", "`income.text`"]
      },
      "criteria": {"true": {"what": "..."}, "false": {"what": "..."}}
    },
    "severity": {"type": "score", "instructions": {"question": "...", "compare": ["`household.text`", "`income.text`"]}, "criteria": ["...", "...", "..."]}
  }
}
```

A round-2 request refused as too large is that finding's error; it is not
split, because each confirm reads its passage beside all the others, and a
split would judge a different finding (see How a finding is read).

## Verdict rules

With `{low, high}` as the review band:

- **Evidence of a directly screened concern.** A passage whose confirm is at or
  below `low` is dropped; below `high` it is cited as `:review`; at or above
  `high`, as `:holds`.
- **Evidence of a concern built from factors.** Every passage filling a role
  is cited as `:holds`, once, even if it fills several roles.
- **`:fails`**: any asked check at or below `low`, or no evidence left.
- **`:holds`**: every asked check at or above `high`, and at least one
  citation holds.
- **`:review`**: everything else.

## How a finding is read

A confirm does not judge its passage alone. It reads the passage's part in
the whole finding, beside every other passage gathered with it, so a line
that refers back to another ("I kind of resent it") can hold beside the line
it refers to and fail alone. That was measured on conversation transcripts,
where lines lean on turns far away; a source of self-contained passages may
behave differently. Three things follow:

- **A finding's evidence is judged as a set.** Show a finding's citations
  together. One citation shown alone is something the model never judged
  alone.
- **Gathering shapes judgment.** `threshold` decides which passages are
  gathered, and so what every confirm reads. A passage near the threshold
  can move a sibling's verdict across the review band from run to run:
  round-1 noise reaches round 2.
- **A finding is one request.** Round 2 never splits a finding, so a larger
  finding is a larger request, not more of them.

## Replies

The client's reply is checked once, in the shell. A reply that skips a
question, or answers one with a value its question cannot have, is not a
verdict on it: the whole request becomes a `Cite.Error` with
`{:missing_answers, keys}` or `{:malformed_answers, keys}`, and nothing from
it is read. A Noul or a confidence must be a probability from 0 to 1, a
Score a level index from 0 to its last level, and a Choice one of its
options.
