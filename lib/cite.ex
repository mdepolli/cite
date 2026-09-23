defmodule Cite do
  @moduledoc """
  Judgments plus grounding: findings about a document, each citing the
  caller's own passages, unchanged.

  Three steps:

      defmodule MyApp.Riddles do                       # declare the policy once
        use Cite.Policy

        concern :riddle do
          indicator do
            question "Does {passage} pose a riddle?"
            yes "A question asked to be puzzled over."
            no "A plain question, a statement, or a remark."
          end
        end
      end

      source = Cite.source(lines)                      # hand over the passages
      report = Cite.judge(client, source, MyApp.Riddles) # judge the source against it

  `judge/4` runs two fixed rounds: a screen of every passage for every
  indicator, then one judgment per finding. A decision model answers typed
  questions about the passages; it never writes text and never sees a
  passage the caller did not list.

  ## The client

  `client/2` builds one from a `Cite.Provider` module. Any 1-arity function
  of the same shape works in its place:

      request -> {:ok, verdict} | {:error, reason}

  where `request` is `%{"state" => map(), "questions" => map()}` and
  `verdict` is `%{answers: map(), usage: usage | nil}` plus `model`, the
  versioned id that answered, when the provider reports it.
  """

  alias Cite.{Report, Run, Source}

  @type usage :: Report.usage()
  @type verdict :: %{
          required(:answers) => map(),
          required(:usage) => usage() | nil,
          optional(:model) => String.t()
        }
  @type client :: (map() -> {:ok, verdict()} | {:error, term()})

  @doc """
  A client backed by `provider`, a module implementing `Cite.Provider`;
  `opts` are the provider's. Build it once, where the credentials live, and
  pass it in.

      client = Cite.client(Cite.Provider.TypeSafe, api_key: System.fetch_env!("JEV_API_KEY"))
  """
  @spec client(module(), keyword()) :: client()
  def client(provider, opts \\ []) when is_atom(provider) and is_list(opts) do
    handle = provider.new(opts)
    &provider.judge(handle, &1)
  end

  @doc """
  The source: the caller's passages, each a text or `%{text: text}` with
  optional `:id` and `:meta`. Options: `as` (`"passages"`), the word the
  passages sit under in every request; `show` (`[]`), the meta keys the
  model sees. See `Cite.Source`.
  """
  @spec source([String.t() | map()], keyword()) :: Source.t()
  defdelegate source(units, opts \\ []), to: Source, as: :new

  @doc """
  Judges `source` against `policy`, a module that uses `Cite.Policy`.
  Options: `threshold` (0.5), the round-1 score a match must exceed;
  `review_band` (`{0.4, 0.6}`); `window` (40), passages per round-1 request;
  `max_evidence` (20), passages a finding may cite.
  """
  @spec judge(client(), Source.t(), module(), keyword()) :: Report.t()
  defdelegate judge(client, source, policy, opts \\ []), to: Run
end
