# Triaging logs

This guide builds a policy that reads log lines and sorts them the way an
operator on call would: which lines are alerts, what kind of alert each
one is, and which only look alarming. Every answer cites the line it came
from, so you can check it at a glance.

It assumes you know your logs and have not used Cite before. The examples
are real lines from BGL, the BlueGene/L supercomputer log published in
Loghub (Zhu et al., ISSRE 2023; Oliner and Stearley, DSN 2007; CC BY 4.0).
Swap in your own lines as you go.

## What you will build

A policy module, a few lines of code that run it, and a table like this:

| Line | Text | Kind |
|---|---|---|
| L003 | `machine check interrupt (bit=0x10): L2 DCU read error` | hardware error |
| L004 | `rts: kernel terminated for reason 1002` | kernel crash |
| L005 | `ciod: LOGIN chdir(/home/auselton/testing) failed: No such file or directory` | no alert |
| L006 | `machine check enable..............0` | no alert |

The last two are the reason to use a model here. Both contain words that
page people ("failed", "machine check"), and neither is an alert: one is a
user's wrong path, the other a field printed in a register dump.

## 1. Write down the decisions you already make

Before any code, list the kinds of alert you would page someone for, in
your own words, one line each. For BGL:

- **Processor exception**: a node's processor took an exception that
  stopped the program on it.
- **Hardware error**: a machine check, or an uncorrectable memory, cache,
  or network error.
- **Kernel crash**: the kernel or runtime on a node panicked or terminated.
- **Filesystem**: a mount failed, or the filesystem returned an I/O error.
- **Lost connection**: a link between nodes, or to an I/O node, was lost,
  reset, or timed out.
- **Job resources**: a job could not start for lack of memory, processes,
  or a free device.
- **Power and links**: power was lost, or a link card or switch failed.

Then list what looks like an alert and is not. This list matters as much
as the first:

- a user's program that will not load, or a path that does not exist;
- an error the hardware reports it corrected;
- the dozens of lines a crash prints afterwards, one register field each.

Each alert kind becomes a **concern**. Each lookalike ends up in a `no`
criterion or, when it looks like everything, in a **filter**.

## 2. Turn lines into a source

A source is your lines as passages. One log line is one passage: that is
the unit you triage and the unit you want cited.

```elixir
lines = [
  %{id: "L000", text: "data TLB error interrupt", meta: %{component: "KERNEL", time: "2005-06-11-18.01.53.500378"}},
  %{id: "L001", text: "Lustre mount FAILED : bglio856 : point /p/gb1", meta: %{component: "KERNEL", time: "2005-09-05-11.39.48.578783"}},
  # ...
]

source = Cite.source(lines, as: "lines", show: [:component])
```

- `as: "lines"` is the word the model reads the passages under. Use the
  word you would use.
- `show: [:component]` lets the model see which component logged each
  line, as an operator would glance at it. Every other `meta` key stays
  with you.
- Leave the timestamp unshown. Each line is judged on what it says; a time
  beside it adds nothing to that and gives the model something to
  over-read. Keep it in `meta` for your own use, such as grouping a burst
  of alerts afterwards.
- Give each line an id you can trace back, such as its line number in the
  file. Text is kept byte for byte.

## 3. Set noise aside with a filter

After a crash, BGL's kernel prints its registers, one field per line:

```text
machine check enable..............0
data store interrupt caused by icbi.........0
force load/store alignment...............0
```

The field names read like events ("machine check", "interrupt"), so every
concern would have to argue them away in its `no`. A filter does it once:
a passage that fails a filter is evidence for nothing.

```elixir
filter :reports_event do
  question "Does {passage} report something that happened on the machine, rather than print one field or value of a register dump?"
  yes "The line reports an event, a failure, or a state change in words."
  no "The line prints a status field as a name, a row of dots, and a 0 or 1, or prints a register's or address's values: detail from a dump, whatever the field is named after, even when its name is an interrupt or exception followed by the dots and a digit."
end
```

Use a filter only for lines that are never evidence of anything. A line
that is not an alert of one kind but could be of another belongs in that
concern's `no`, not in a filter.

## 4. Write one concern per kind of alert

A concern screened directly has a **detect**: one yes/no question asked of
every line. `yes` and `no` say what each answer covers. Word the question
as an operator would describe the alert, not after the log's message
templates: the model reads meaning, and your wording is what it matches.

Start with the pair whose boundary is hardest. A processor exception and a
hardware error both arrive as "interrupts":

```text
data storage interrupt                                      processor exception
program interrupt                                           processor exception
machine check interrupt (bit=0x10): L2 DCU read error       hardware error
external input interrupt (unit=0x02 bit=0x00): uncorrectable torus error    hardware error
external input interrupt (unit=0x02 bit=0x0d): torus sender z+ retransmission error was corrected    no alert
```

Each concern names the other in its `no`, so the model does not have to
guess where the line between them falls:

```elixir
concern :cpu_exception do
  detect do
    question "Does {passage} report that a node's processor took an exception or interrupt that stopped the program running on it: a memory-access fault, an illegal instruction, an unavailable unit, or an unexpected interrupt?"
    yes "The line names the exception or interrupt the processor took, whatever caused it, software or hardware."
    no "Any other line, including a machine check or uncorrectable hardware error, which is a hardware error."
  end
end

concern :hardware_error do
  detect do
    question "Does {passage} report a hardware error on a node: a machine check, or an uncorrectable error in its memory, cache, or network hardware, or a failed hardware mechanism?"
    yes "The line itself reports the hardware error: a machine check, an uncorrectable memory, cache, or torus error, or a hardware mechanism that failed."
    no "Any other line, including an error that was corrected, or a processor exception such as a memory-access fault or illegal instruction."
  end
end
```

The corrected torus error is covered by "an error that was corrected" in
`hardware_error`'s `no`. The user's mistakes go in the `no` of the concerns
they resemble:

```elixir
concern :job_resources do
  detect do
    question "Does {passage} report that a job could not start because the system lacked a resource: memory, processes, or a device that was busy or unavailable?"
    yes "Setting up or launching a job failed because memory could not be allocated, no process was available, or a resource was busy or temporarily unavailable."
    no "Any other line, including a job that failed because the user's program, file, or path was wrong."
  end
end
```

That `no` is what keeps `ciod: Error loading /home/yates//bandwidth.rts:
invalid or missing program image, No such file or directory` out, while
`ciod: Error creating node map from file ...: Cannot allocate memory` is
in.

A few rules from practice:

- **One proposition per question.** "Did it crash *and* was it the kernel"
  gets whichever half the model weighs more.
- **The `no` holds the lookalikes you have met.** When a wrong answer
  surprises you, the explanation you would give a new colleague is the
  missing `no`.
- **Name concerns after the alert, not the message.** `:kernel_crash`, not
  `:rts_terminated`: a new message for the same event should still land.

The full policy is at the end of this guide. More on the language in
[Writing policies](../writing-policies.md).

## 5. Run it

```elixir
client = Cite.client(Cite.Provider.TypeSafe, api_key: System.fetch_env!("JEV_API_KEY"))
report = Cite.judge(client, source, MyApp.LogTriage)
```

Cite screens every line for every detect and filter, in windows of 40 lines
per request, then judges each kind of alert that matched, in one request
per kind. A thousand lines under seven concerns cost about 25 screening
requests and at most 7 judging requests.

Keep the defaults at first. `window` sets lines per screening request.
Leave `threshold` at 0.5: lowering it gathers more lines into each
judgment, which changes verdicts and invents alerts, it does not simply
catch more (see [How judging works](../how-judging-works.md)).

## 6. Read the report as a classification

The report lists findings, one per kind of alert that matched. Each
finding cites its lines, each with a verdict:

- `:holds`: this line is this kind of alert.
- `:review`: the model is unsure. Put it in front of a person; it is not a
  no.

Turn it into one row per line:

```elixir
defmodule MyApp.Triage do
  alias Cite.{Citation, Error, Finding, Passage, Report, Source}

  # Every line of the source, with the kinds it was cited for, :unjudged
  # where a request failed and nothing cited it, or :no_alert.
  def classify(%Source{passages: passages}, %Report{findings: findings, errors: errors}) do
    kinds =
      for %Finding{concern: concern, evidence: evidence} <- findings,
          %Citation{passage: %Passage{id: id}, verdict: verdict} <- evidence,
          reduce: %{} do
        acc -> Map.update(acc, id, [{concern, verdict}], &[{concern, verdict} | &1])
      end

    unjudged = MapSet.new(for %Error{passage_ids: ids} <- errors, id <- ids, do: id)

    for %Passage{id: id, text: text} <- passages do
      {id, text, row(Map.get(kinds, id, []), MapSet.member?(unjudged, id))}
    end
  end

  defp row([], true), do: :unjudged
  defp row([], false), do: :no_alert
  defp row(kinds, _unjudged), do: Enum.reverse(kinds)
end
```

Three things to handle deliberately:

- **A line can be several kinds.** `external input interrupt (unit=0x02
  bit=0x00): uncorrectable torus error` is a hardware error in the torus
  network, and it was cited as both a hardware error and a lost connection.
  Keep both, or decide by your own precedence; Cite does not choose for
  you.
- **Review is a queue, not a verdict.** Page on `:holds`; send `:review` to
  a person with the line and its neighbours.
- **An error is not a "no alert".** A failed request lands in
  `report.errors` with the ids of the lines it covered. Those lines were not
  judged; retry them or show them as unjudged.

`report.screen` keeps every line's round-one score for every question. It
is how you find out why a line was or was not considered.

## 7. Check it against lines you have triaged

Take a few hundred lines you or your team have already sorted, including
plenty of lookalikes, and label each with its kind or "none". Run the
policy on them and compare:

- A line you called an alert that Cite did not cite: find its score in
  `report.screen`. Below 0.5 means the detect's wording missed it.
- A line Cite cited that you did not: read the `no` of that concern. The
  explanation you would give is usually the missing part.

Change one thing at a time, and keep some labelled lines aside that you
never read while rewording; check them once you stop.
[Tuning against labels](../writing-policies.md#tuning-against-labels) has the
method.

## 8. When not to use Cite

If your messages come from a fixed set of templates, and a template always
means the same kind of alert, a lookup table keyed on the template is
cheaper and exact. BGL is close to that: within its fatal lines, a message
template always carries the same tag.

Cite earns its place where a table cannot: free-text messages, new
templates your table has never seen, and boundaries that depend on what a
line means (a corrected error, a user's wrong path, a register field named
after an interrupt). Start with the table where you can, and send what it
does not match to Cite.

## The whole policy

```elixir
defmodule MyApp.LogTriage do
  use Cite.Policy

  filter :reports_event do
    question "Does {passage} report something that happened on the machine, rather than print one field or value of a register dump?"
    yes "The line reports an event, a failure, or a state change in words."
    no "The line prints a status field as a name, a row of dots, and a 0 or 1, or prints a register's or address's values: detail from a dump, whatever the field is named after, even when its name is an interrupt or exception followed by the dots and a digit."
  end

  concern :cpu_exception do
    detect do
      question "Does {passage} report that a node's processor took an exception or interrupt that stopped the program running on it: a memory-access fault, an illegal instruction, an unavailable unit, or an unexpected interrupt?"
      yes "The line names the exception or interrupt the processor took, whatever caused it, software or hardware."
      no "Any other line, including a machine check or uncorrectable hardware error, which is a hardware error."
    end
  end

  concern :hardware_error do
    detect do
      question "Does {passage} report a hardware error on a node: a machine check, or an uncorrectable error in its memory, cache, or network hardware, or a failed hardware mechanism?"
      yes "The line itself reports the hardware error: a machine check, an uncorrectable memory, cache, or torus error, or a hardware mechanism that failed."
      no "Any other line, including an error that was corrected, or a processor exception such as a memory-access fault or illegal instruction."
    end
  end

  concern :kernel_crash do
    detect do
      question "Does {passage} report that the kernel or runtime on a node crashed, panicked, failed an assertion, or terminated abnormally?"
      yes "The line says the kernel or runtime panicked, terminated, stopped execution, or failed an internal assertion."
      no "Any other line, including a diagnostic detail printed alongside a crash, or an application that exited on its own error."
    end
  end

  concern :filesystem do
    detect do
      question "Does {passage} report that the system failed to mount or reach a filesystem, or got an I/O error from one?"
      yes "A mount failed, or a filesystem operation failed with an input/output error on the system's side."
      no "Any other line, including a path that does not exist or a file a user named wrongly, which is the user's mistake, not a filesystem fault."
    end
  end

  concern :io_connection do
    detect do
      question "Does {passage} report that a connection between nodes, or between a node and its I/O or service node, was lost, reset, timed out, or delivered corrupt packets?"
      yes "A socket, link, or network connection was severed, reset, timed out, or closed unexpectedly; a read from or write to one failed; or packets arrived malformed."
      no "Any other line, including a connection closed normally, an error the hardware says was corrected, or a failure unrelated to communication."
    end
  end

  concern :job_resources do
    detect do
      question "Does {passage} report that a job could not start because the system lacked a resource: memory, processes, or a device that was busy or unavailable?"
      yes "Setting up or launching a job failed because memory could not be allocated, no process was available, or a resource was busy or temporarily unavailable."
      no "Any other line, including a job that failed because the user's program, file, or path was wrong."
    end
  end

  concern :power_and_links do
    detect do
      question "Does {passage} report a power failure, or a failure in the link cards and switches that connect the machine's midplanes?"
      yes "Power or a power-good signal was lost on a card, or a link card or midplane switch operation failed or a port disconnected."
      no "Any other line."
    end
  end
end
```
