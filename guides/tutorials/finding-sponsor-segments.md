# Finding sponsor segments

This guide builds a policy that reads a video's captions and finds its
sponsor reads: where the creator advertises something they were paid to
place. The result is a list of time ranges, each backed by the caption
text it came from, ready for a skip button, an ad-disclosure check, or a
review queue.

It assumes you know a sponsor read when you hear one and have not used Cite
before. The caption lines below are invented, written the way YouTube's
automatic captions come out: lowercase, no punctuation.

## What you will build

A policy module, the code that runs it on one video, and a list like this:

```text
03:12–04:05  sponsor  (4 chunks)
17:40–18:02  sponsor  (2 chunks)
```

The hard part is not the read that says "this video is sponsored by". It is
everything around it: the lead-in that does not name the sponsor yet, the
hand-back to the video, and the products a video mentions without being
paid to.

## 1. Decide what counts

Before any code, write down what you would mark, in your own words.

A sponsor read is a stretch where the creator advertises a product,
service, or company that paid for the placement. All of it counts:

- the lead-in: "before we get into it i want to tell you about something
  that's been saving me a ton of time";
- the pitch: what the product is and why they use it;
- the offer: the code, the discount, the link in the description;
- the hand-back: "anyway thanks to them for sponsoring and let's get back
  into it".

Then write down what sounds like an ad and is not. This list decides your
precision:

- the creator's own merch, Patreon, course, or other videos;
- "like and subscribe" and other requests to the viewer;
- a product the video is about. A review of a camera names the camera,
  praises it, and may even link it, and nobody paid to put it there.

If you also want self-promotion or "like and subscribe" found, make them
concerns of their own later. Start with the one you need.

## 2. Turn captions into a source

Automatic captions have no sentences, only timed lines of a few words. Group
them into chunks by time, about 20 seconds each, and make each chunk a
passage:

```elixir
chunks = [
  %{id: "c0192", text: "okay so before we get into the build i want to tell you about something that's been saving me a ton of time", meta: %{start: 192.0, finish: 211.5}},
  %{id: "c0212", text: "it's a password manager called keyvault and honestly i put off setting one up for years", meta: %{start: 212.0, finish: 231.8}},
  # ...
]

source = Cite.source(chunks, as: "chunks")
```

- **Chunk size is the main decision.** Small enough that a chunk says where
  a read is; big enough that a read spans several chunks, so each has some
  context of its own. Twenty seconds holds a sentence or two of speech.
  Cite judges a finding's chunks together in the second round, so a chunk
  that only says "use code build twenty" is read beside the chunks that
  name the sponsor.
- **Keep the times in `meta`, unshown.** `start` and `finish` are for you,
  to turn citations back into timestamps. The model judges what is said,
  and a timestamp beside it adds nothing.
- **Give each chunk an id you can trace,** such as its start second.
  `as: "chunks"` is the word the model reads the passages under.

## 3. Write the concern

One concern with a detect: a yes/no question asked of every chunk.

```elixir
defmodule MyApp.Sponsors do
  use Cite.Policy

  concern :sponsor do
    detect do
      question "Is {passage} part of a paid sponsor read: a stretch of the video where the creator advertises a product, service, or company that paid for the placement?"

      yes "The creator names a sponsor or partner, describes or recommends its product, or gives its offer, discount code, or link, as part of an advertisement in the video. A passage that carries any of the read counts, its lead-in, its call to action, or its hand-back to the video, even when the rest of the passage is the video's own content."

      no "Any other passage, including the creator promoting their own channel, merchandise, Patreon, or other videos, asking viewers to like or subscribe, or discussing a product as part of the video's own subject without being paid to."
    end
  end
end
```

Three choices in that wording carry most of the result:

- **"Part of a paid sponsor read", not "a sponsor read".** A chunk rarely
  holds a whole read. Asking whether it is one misses the lead-in and the
  hand-back; asking whether it is part of one does not.
- **"Even when the rest of the passage is the video's own content."** A
  chunk where the read ends and the video resumes is half ad, half not.
  Say which way it goes, or the model will decide differently from chunk
  to chunk.
- **The `no` names every lookalike from step 1.** "A product the video is
  about" is the one that matters most: without it, every review is an ad.

More on the language in [Writing policies](../writing-policies.md).

## 4. Run it

```elixir
client = Cite.client(Cite.Provider.TypeSafe, api_key: System.fetch_env!("JEV_API_KEY"))
report = Cite.judge(client, source, MyApp.Sponsors)
```

Cite screens every chunk in windows of 40 per request, then judges the
chunks that matched together, in one request. A 20-minute video is about 60
chunks: two screening requests and one judging request.

Keep `threshold` at its default of 0.5. Lowering it gathers more chunks
into the one judgment, which changes how every chunk in it is read (see
[How judging works](../how-judging-works.md)).

## 5. From citations to segments

The finding for `:sponsor` cites its chunks, each `:holds` or `:review`.
Merge chunks that sit next to each other into time ranges:

```elixir
defmodule MyApp.Segments do
  alias Cite.{Citation, Finding, Passage, Report}

  # Held chunks merged into {start, finish} ranges, where a gap of at most
  # `gap` seconds joins two chunks into one segment.
  def sponsor_segments(%Report{findings: findings}, gap \\ 1.0) do
    findings
    |> Enum.flat_map(&held_times/1)
    |> Enum.sort()
    |> Enum.reduce([], &merge(&1, &2, gap))
    |> Enum.reverse()
  end

  defp held_times(%Finding{concern: :sponsor, evidence: evidence}) do
    for %Citation{verdict: :holds, passage: %Passage{meta: meta}} <- evidence,
        do: {meta.start, meta.finish}
  end

  defp held_times(%Finding{}), do: []

  defp merge({start, finish}, [{s, f} | rest], gap) when start - f <= gap,
    do: [{s, max(f, finish)} | rest]

  defp merge(range, acc, _gap), do: [range | acc]
end
```

- **`:review` is a question for a person,** not a no. Show those chunks
  with a few seconds around them.
- **A failed request is not "no sponsor".** It lands in `report.errors` with
  the ids it covered; those chunks were not judged. Retry them, or mark the
  video as not checked.
- **Segments are as precise as your chunks.** A range starts at the first
  cited chunk's start, which may be a few seconds before the read begins.
  If you need tighter edges, look inside the first and last chunk with the
  caption lines' own times.

## 6. Check it against labels

To know how well the policy works, compare it with segments someone else
marked. SponsorBlock's crowd-sourced segments are the obvious reference,
and they have two traps:

- **The crowd misses reads.** A read nobody marked counts as your false
  alarm. On crowd labels, most of a good policy's "false alarms" are sponsor
  reads nobody submitted. Before you change a word to remove one, have
  someone who has not seen your results read those chunks, alongside chunks
  nobody cited, and judge them blind. Measure precision against that
  reading.
- **Your label rule must ask your question.** Turning a marked time span
  into chunk labels takes a rule, such as "a chunk counts when five seconds
  of it fall inside the span". If the rule counts a chunk that is mostly
  the video, and your question asks about a read, those chunks show up as
  misses that no wording will fix. Look at where misses fall before you
  reword.

Change one thing at a time, and keep some videos aside that you never read
while rewording, from channels you did not tune on.
[Tuning against labels](../writing-policies.md#tuning-against-labels) has the
method.

## 7. When not to use Cite

A keyword rule ("sponsored by", "use code", "link in the description") is
cheap and rarely wrong when it fires. It misses most reads, which do not
announce themselves: a lead-in, a pitch that never says "sponsor", a code
read out without the word. If you only need to flag videos that disclose
a sponsorship in so many words, the rule is enough. Cite is for finding
the whole read, and the reads that do not say what they are.
