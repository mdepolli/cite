defmodule Cite do
  @moduledoc """
  Citations copied from the source, never written by a model.

  Your code lists the candidates — a line in a transcript, a row, a sentence —
  a decision model judges which ones hold up, and Cite returns those exact
  bytes. A decision model answers narrow typed questions — a probability, a
  level, a choice — with calibrated confidence; it never generates text.

  ## Inputs

    * `Cite.Candidate.from_segments/1` builds the candidates.
    * `Cite.Question.noul/1`, `score/1`, `choice/1` build the questions.
    * `Cite.Cluster.new/1` builds what `compose` returns.

  ## Outputs

  `select/5` returns a `Cite.Result` of `Cite.Span`s and `Cite.Error`s. Read
  them; do not build them.

  ## The client

  `new/2` builds one from a `Cite.Provider` module. Any 1-arity function of
  the same shape works in its place:

      request -> {:ok, verdict} | {:error, reason}

  where `verdict` is `%{answers: map(), usage: usage | nil}` — plus `model`,
  the versioned id that answered, when the provider reports it — and
  `usage` is `%{input_tokens: n, output_tokens: n}`. Requests are wire-shaped (string
  keys); Cite encodes questions at that edge, so callers never see them.

  ## The spec

  `spec.atomics` is a list of `%{name: String.t(), question: (Candidate.t() -> Question.t())}`,
  each question a Noul — the index holds probabilities.
  Scan keys are `"\#{candidate.id}:\#{atomic.name}"`.

  `spec.scan_key` (default `"candidates"`) is the state key each scan window
  sits under, and so the word every scan question names in its path —
  `` `utterances.U005.text` `` for a transcript, say. It lives in the spec
  because it belongs to the questions, not to a run.

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

  alias Cite.{Candidate, Cluster, Question, Result, Select}

  @type usage :: Result.usage()
  @type verdict :: %{
          required(:answers) => map(),
          required(:usage) => usage() | nil,
          optional(:model) => String.t()
        }
  @type client :: (map() -> {:ok, verdict()} | {:error, term()})
  @type atomic :: %{name: String.t(), question: (Candidate.t() -> Question.t())}
  @type spec :: %{
          required(:atomics) => [atomic()],
          required(:compose) => (map(), [Candidate.t()] -> [Cluster.t()]),
          optional(:scan_key) => String.t()
        }

  @doc """
  A client backed by `provider`, a module implementing `Cite.Provider`;
  `opts` are the provider's. The result is the 1-arity function `select/5`
  takes. Cite ships `Cite.Provider.TypeSafe`. Build it once, where the
  credentials live, and pass it in.

      client = Cite.new(Cite.Provider.TypeSafe, api_key: System.fetch_env!("JEV_API_KEY"))
  """
  @spec new(module(), keyword()) :: client()
  def new(provider, opts \\ []) when is_atom(provider) and is_list(opts) do
    handle = provider.new(opts)
    &provider.judge(handle, &1)
  end

  @doc """
  Runs select-and-judge. Options: `window_size` (40), `atomic_threshold`
  (0.5), `review_band` (`{0.4, 0.6}`), `confidence_floor` (0.5), `state`
  (`%{}`, merged under every request).
  """
  @spec select(client(), String.t(), [Candidate.t()], spec(), keyword()) :: Result.t()
  defdelegate select(client, source, candidates, spec, opts \\ []), to: Select
end
