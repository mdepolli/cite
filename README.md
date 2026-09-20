# Cite

Candidates in, grounded citations out.

Cite proposes candidates, asks an [Arbiter](https://github.com/mdepolli/arbiter)
System One judge, and copies evidence byte-exact from the source — never a
paraphrased quote to align.

```elixir
judge = Arbiter.new(api_key: System.fetch_env!("JEV_API_KEY"))
{source, candidates} = Cite.Candidate.from_segments(segments)

result =
  Cite.select(judge, source, candidates, spec)
```

## Installation

```elixir
def deps do
  [
    {:cite, "~> 0.1.0"}
  ]
end
```

## License

MIT — see [LICENSE](LICENSE).
