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

  `judge/2` builds one from a `Cite.Provider` (TypeSafe System One by
  default). Any 1-arity function of the same shape works in its place:

      request -> {:ok, verdict} | {:error, reason}

  where `verdict` is `%{answers: map(), usage: usage | nil}` and `usage` is
  `%{input_tokens: n, output_tokens: n}`. Requests are wire-shaped (string
  keys); Cite encodes questions at that edge, so callers never see them.

  ## The spec

  `spec.atomics` is a list of `%{name: String.t(), question: (Candidate.t() -> Question.t())}`.
  Scan keys are `"\#{candidate.id}:\#{atomic.name}"`.

  `spec.compose` is `index, candidates -> [Cluster.t()]`. `index` is
  `%{candidate_id => %{atomic_name => noul}}` after `atomic_threshold`;
  candidates whose scan window failed have no row, so look them up with
  `Map.get/2`, not `Map.fetch!/2`. A
  `%Candidate{}` placed in a cluster's `state` is wired as its `meta` plus
  `"id"` and `"text"`; the scan puts each window's candidates under
  `"candidates"` in the same shape.

  Compare attributes are typed from `cluster.questions`: each `:score` emits
  `round(score)` under its key, each `:choice` emits `choice`; both become
  `"uncertain"` when confidence is below `confidence_floor`. Cite knows no
  question names; the caller maps score integers to its own labels.
  """

  alias Cite.{Candidate, Cluster, Provider, Question, Result, Select}

  @type usage :: Result.usage()
  @type verdict :: %{answers: map(), usage: usage() | nil}
  @type judge :: (map() -> {:ok, verdict()} | {:error, term()})
  @type atomic :: %{name: String.t(), question: (Candidate.t() -> Question.t())}
  @type spec :: %{atomics: [atomic()], compose: (map(), [Candidate.t()] -> [Cluster.t()])}

  @doc """
  A TypeSafe System One judge; `opts` are `Cite.Provider.TypeSafe`'s
  (`:api_key` or `JEV_API_KEY`, `:model`, `:base_url`, `:req_options`).
  Given a `Cite.Provider` module instead, a judge backed by it with no
  options — see `judge/2`.
  """
  @spec judge(keyword() | module()) :: judge()
  def judge(opts_or_provider \\ [])
  def judge(opts) when is_list(opts), do: judge(Provider.TypeSafe, opts)
  def judge(provider) when is_atom(provider), do: judge(provider, [])

  @doc """
  A judge backed by `provider`, any module implementing `Cite.Provider`;
  `opts` are the provider's. The result is the 1-arity function
  `select/5` takes, closed over the provider's client.
  """
  @spec judge(module(), keyword()) :: judge()
  def judge(provider, opts) when is_atom(provider) and is_list(opts) do
    client = provider.new(opts)
    &provider.judge(client, &1)
  end

  @doc """
  Runs select-and-judge. Options: `window_size` (40), `atomic_threshold`
  (0.5), `review_band` (`{0.4, 0.6}`), `confidence_floor` (0.5), `state`
  (`%{}`, merged under every request).
  """
  @spec select(judge(), String.t(), [Candidate.t()], spec(), keyword()) :: Result.t()
  defdelegate select(judge, source, candidates, spec, opts \\ []), to: Select
end
