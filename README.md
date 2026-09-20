# Cite

Candidates in, grounded citations out.

Code proposes candidates, a System One judge answers narrow typed questions
about them, and Cite copies evidence byte-exact from the source — never a
paraphrased quote to align.

```elixir
candidates = Cite.Candidate.from_segments(segments)
source = Enum.map_join(candidates, " ", & &1.text)

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
