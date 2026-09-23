defmodule Cite.Run do
  @moduledoc """
  One judging run, passed through every step of `Cite.judge/4`. It starts as
  what the caller gave, validated once, and each step fills in its part:
  round 1 the `screen`, gathering the `gathered` findings, round 2 the
  `findings`. Both rounds add their `errors`, `usages`, and `models`.
  Internal; use `Cite.judge/4`.
  """

  alias Cite.{Error, Finding, Screen, Source}
  alias Cite.Gather.Finding, as: Gathered
  alias Cite.Policy.{Build, Terms}

  @schema Spark.Options.new!(
            threshold: [
              type: :number,
              default: 0.5,
              doc: "The round-1 score a match must exceed. Sets recall only."
            ],
            review_band: [
              type: {:custom, __MODULE__, :review_band, []},
              default: {0.4, 0.6},
              doc: """
              `{low, high}`, `low < high`. At or below `low` a passage is \
              dropped and a check fails; at or above `high` either holds.\
              """
            ],
            window: [
              type: :pos_integer,
              default: 40,
              doc: "Passages per round-1 request."
            ],
            max_evidence: [
              type: :pos_integer,
              default: 20,
              doc: "Passages a finding may cite; the rest are `over_cap`."
            ]
          )

  @type t :: %__MODULE__{
          client: Cite.client(),
          source: Source.t(),
          terms: Terms.t(),
          threshold: number(),
          review_band: {number(), number()},
          window: pos_integer(),
          max_evidence: pos_integer(),
          screen: Screen.screen(),
          gathered: [Gathered.t()],
          findings: [Finding.t()],
          errors: [Error.t()],
          usages: [Cite.usage() | nil],
          models: [String.t()]
        }

  @enforce_keys [:client, :source, :terms, :threshold, :review_band, :window, :max_evidence]
  defstruct @enforce_keys ++
              [screen: %{}, gathered: [], findings: [], errors: [], usages: [], models: []]

  @doc false
  @spec options_docs() :: String.t()
  def options_docs, do: Spark.Options.docs(@schema)

  @doc """
  A run of `source` against `policy_module`. Raises `ArgumentError` on an
  option it cannot use, or a module that is not a policy.
  """
  @spec new(Cite.client(), Source.t(), module(), keyword()) :: t()
  def new(client, %Source{} = source, policy_module, opts)
      when is_function(client, 1) and is_atom(policy_module) and is_list(opts) do
    case Spark.Options.validate(opts, @schema) do
      {:ok, options} ->
        struct!(
          __MODULE__,
          [client: client, source: source, terms: Build.read(policy_module)] ++ options
        )

      {:error, error} ->
        raise ArgumentError, Exception.message(error)
    end
  end

  @doc false
  def review_band({low, high} = band) when is_number(low) and is_number(high) and low < high,
    do: {:ok, band}

  def review_band(other),
    do: {:error, "expected {low, high} with low < high, got: #{inspect(other)}"}
end
