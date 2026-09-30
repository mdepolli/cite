defmodule Cite.Run do
  @moduledoc """
  One judging run, passed through every step of `Cite.judge/4`. It starts as
  what the caller gave, validated once, and each step fills in its part:
  round 1 fills `screen`, gathering fills `gathered`, and round 2 fills
  `findings`. Both rounds add their `errors`, `usages`, and `models`.
  Internal; use `Cite.judge/4`.
  """

  alias Cite.{Error, Finding, Gathered, Screen, Source}
  alias Cite.Policy.{Build, Terms}

  @schema Spark.Options.new!(
            threshold: [
              type: {:custom, __MODULE__, :threshold, []},
              default: 0.5,
              doc: """
              The round-1 score a filter, factor, or detect must exceed, from 0 to 1. \
              It decides which passages are gathered, and a finding's confirms read \
              every passage gathered with it, so it changes verdicts as well as \
              recall. Below 0.5, measured on transcripts, it invents findings in \
              concerns with no match at 0.5 and multiplies review load.\
              """
            ],
            review_band: [
              type: {:custom, __MODULE__, :review_band, []},
              default: {0.4, 0.6},
              doc: """
              `{low, high}`, `0 <= low < high <= 1`. At or below `low` a passage is \
              dropped and a check fails; at or above `high` either holds.\
              """
            ],
            window: [
              type: :pos_integer,
              default: 40,
              doc: """
              Passages per round-1 request, a positive integer. At `1`, each \
              request holds one passage.\
              """
            ],
            concurrency: [
              type: :pos_integer,
              default: 4,
              doc: """
              The most requests in flight at once within a round. The rounds run \
              one after the other, and the report is the same at any setting. Set \
              it within the provider's rate limits; at `1`, requests go out one at \
              a time.\
              """
            ]
          )

  @type t :: %__MODULE__{
          client: Cite.client(),
          source: Source.t(),
          terms: Terms.t(),
          threshold: number(),
          review_band: {number(), number()},
          window: pos_integer(),
          concurrency: pos_integer(),
          screen: Screen.screen() | nil,
          gathered: [Gathered.t()] | nil,
          findings: [Finding.t()] | nil,
          errors: [Error.t()],
          usages: [Cite.usage() | nil],
          models: [String.t()]
        }

  # A stage's output is nil until its step runs, and the next step matches
  # on it, so steps run out of order fail loudly instead of reading an empty
  # result. Errors, usages, and models start empty: both rounds add to them.
  @enforce_keys [:client, :source, :terms, :threshold, :review_band, :window, :concurrency]
  defstruct @enforce_keys ++
              [screen: nil, gathered: nil, findings: nil, errors: [], usages: [], models: []]

  @doc false
  @spec options_docs() :: String.t()
  def options_docs, do: Spark.Options.docs(@schema)

  @doc """
  A run of `source` against `policy_module`. Raises `ArgumentError` on a
  client, source, or policy of the wrong kind, or an option it cannot use.
  """
  @spec new(Cite.client(), Source.t(), module(), keyword()) :: t()
  def new(client, source, policy_module, opts) do
    given = [client: client(client), source: source(source), terms: Build.read(policy_module)]

    struct!(__MODULE__, given ++ options(opts))
  end

  defp client(client) when is_function(client, 1), do: client

  defp client(other) do
    raise ArgumentError, "client must be a 1-arity function, got: #{inspect(other)}"
  end

  defp source(%Source{} = source), do: source

  defp source(other) do
    raise ArgumentError,
          "source must be a Cite.Source, built by Cite.source/2, got: #{inspect(other)}"
  end

  defp options(opts) when is_list(opts) do
    case Spark.Options.validate(opts, @schema) do
      {:ok, options} -> options
      {:error, error} -> raise ArgumentError, Exception.message(error)
    end
  end

  defp options(other) do
    raise ArgumentError, "options must be a keyword list, got: #{inspect(other)}"
  end

  # Round-1 scores, confirms, and checks are all probabilities, so the options
  # compared against them are too.
  @doc false
  def threshold(threshold) when is_number(threshold) and threshold >= 0 and threshold <= 1,
    do: {:ok, threshold}

  def threshold(other), do: {:error, "expected a number from 0 to 1, got: #{inspect(other)}"}

  @doc false
  def review_band({low, high} = band)
      when is_number(low) and is_number(high) and 0 <= low and low < high and high <= 1,
      do: {:ok, band}

  def review_band(other),
    do: {:error, "expected {low, high} with 0 <= low < high <= 1, got: #{inspect(other)}"}
end
