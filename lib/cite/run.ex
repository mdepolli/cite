defmodule Cite.Run do
  @moduledoc """
  One judging run: what `Cite.judge/4` was given, validated once. Internal;
  use `Cite.judge/4`.
  """

  alias Cite.Policy.{Build, Terms}
  alias Cite.Source

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
          max_evidence: pos_integer()
        }

  @enforce_keys [:client, :source, :terms, :threshold, :review_band, :window, :max_evidence]
  defstruct @enforce_keys

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
