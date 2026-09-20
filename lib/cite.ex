defmodule Cite do
  @moduledoc """
  Candidates in, grounded citations out.

  Code proposes candidates; a System One judge answers narrow typed questions
  about them; Cite copies evidence byte-exact from the source.

  ## Inputs

    * `Cite.Candidate.from_segments/1` builds the candidates.
    * `Cite.Question.noul/1`, `score/1`, `choice/1` build the questions.
    * `Cite.Cluster.new/1` builds what `compose` returns.

  ## Outputs

  `select/5` returns a `Cite.Result` of `Cite.Span`s and `Cite.Error`s. Read
  them; do not build them.

  ## The judge

  A 1-arity function:

      request -> {:ok, verdict} | {:error, reason}

  where `verdict` is `%{answers: map(), usage: usage | nil}` and `usage` is
  `%{input_tokens: n, output_tokens: n}`. Requests are wire-shaped (string
  keys); Cite encodes questions at that edge, so callers never see them.

  ## The spec

  `spec.atomics` is a list of `%{name: String.t(), question: (Candidate.t() -> Question.t())}`.
  Scan keys are `"\#{candidate.id}:\#{atomic.name}"`.

  `spec.compose` is `index, candidates -> [Cluster.t()]`. `index` is
  `%{candidate_id => %{atomic_name => noul}}` after `atomic_threshold`. A
  `%Candidate{}` placed in a cluster's `state` is wired as its `meta` plus
  `"id"` and `"text"`; the scan puts each window's candidates under
  `"candidates"` in the same shape.

  Compare attributes are typed from `cluster.questions`: each `:score` emits
  `round(score)` under its key, each `:choice` emits `choice`; both become
  `"uncertain"` when confidence is below `confidence_floor`. Cite knows no
  question names; the caller maps score integers to its own labels.
  """

  alias Cite.{Candidate, Cluster, Question, Result, Select}

  @type usage :: Result.usage()
  @type verdict :: %{answers: map(), usage: usage() | nil}
  @type judge :: (map() -> {:ok, verdict()} | {:error, term()})
  @type atomic :: %{name: String.t(), question: (Candidate.t() -> Question.t())}
  @type spec :: %{atomics: [atomic()], compose: (map(), [Candidate.t()] -> [Cluster.t()])}

  @doc """
  Runs select-and-judge. Options: `window_size` (40), `atomic_threshold`
  (0.5), `review_band` (`{0.4, 0.6}`), `confidence_floor` (0.5), `state`
  (`%{}`, merged under every request).
  """
  @spec select(judge(), String.t(), [Candidate.t()], spec(), keyword()) :: Result.t()
  defdelegate select(judge, source, candidates, spec, opts \\ []), to: Select
end
