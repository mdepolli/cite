defmodule Cite.Report do
  @moduledoc """
  What `Cite.judge/4` returns:

  - `findings`: the judged findings, in the policy's concern order.
  - `screen`: every round-1 score, for diagnosis.
  - `errors`: one per failed request.
  - `usage`: tokens totalled across both rounds, or `nil` when the provider
    reported none.
  - `models`: every versioned model id that answered, in order of first
    appearance.

  Read it, don't build it.
  """

  alias Cite.{Error, Finding, Run}

  @derive Jason.Encoder

  @type usage :: %{input_tokens: non_neg_integer(), output_tokens: non_neg_integer()}

  @type t :: %__MODULE__{
          findings: [Finding.t()],
          screen: %{String.t() => %{atom() => number()}},
          errors: [Error.t()],
          usage: usage() | nil,
          models: [String.t()]
        }

  @enforce_keys [:findings, :screen, :errors, :usage, :models]
  defstruct [:findings, :screen, :errors, :usage, :models]

  @doc false
  @spec new(Run.t()) :: t()
  def new(%Run{screen: screen, findings: findings} = run)
      when is_map(screen) and is_list(findings) do
    %__MODULE__{
      findings: run.findings,
      screen: run.screen,
      errors: run.errors,
      usage: total_usage(run.usages),
      models: Enum.uniq(run.models)
    }
  end

  defp total_usage(usages) do
    case Enum.reject(usages, &is_nil/1) do
      [] ->
        nil

      present ->
        %{
          input_tokens: Enum.sum_by(present, & &1.input_tokens),
          output_tokens: Enum.sum_by(present, & &1.output_tokens)
        }
    end
  end
end
