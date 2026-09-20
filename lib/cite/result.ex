defmodule Cite.Result do
  @moduledoc """
  A completed Select run: spans plus errors.

  Span order follows compose emit order (not necessarily document order).
  `errors` holds scan errors first, in window order, then compare errors in
  cluster order. `scan` and `rejected` are set by Select.
  `usage` totals token counts when the provider reported them (`nil`
  otherwise). `models` lists every versioned model id that answered, in
  order of first appearance — one entry on a healthy run, more if the
  provider switched models mid-run, none if it never says.
  """

  alias Cite.{Error, Span}

  @derive [
    {Jason.Encoder, only: [:spans, :errors, :usage, :models, :scan, :rejected]},
    {JSON.Encoder, only: [:spans, :errors, :usage, :models, :scan, :rejected]}
  ]

  @type usage :: %{input_tokens: non_neg_integer(), output_tokens: non_neg_integer()}
  @type scan :: %{String.t() => %{String.t() => number()}}
  @type rejected :: %{String.t() => map()}

  @type t :: %__MODULE__{
          spans: [Span.t()],
          errors: [Error.t()],
          usage: usage() | nil,
          models: [String.t()],
          scan: scan() | nil,
          rejected: rejected() | nil
        }

  @enforce_keys [:spans, :errors, :usage, :models, :scan, :rejected]
  defstruct [:spans, :errors, :usage, :models, :scan, :rejected]

  @doc false
  @spec total_usage([usage() | nil]) :: usage() | nil
  def total_usage(usages) do
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
