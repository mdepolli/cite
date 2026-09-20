defmodule Cite.Result do
  @moduledoc """
  A completed Select run: spans plus errors.

  Span order follows compose emit order (not necessarily document order).
  `scan` and `rejected` are set by Select (`nil` elsewhere).
  `usage` totals token counts when the judge reported them (`nil` otherwise).
  """

  alias Cite.{Error, Span}

  @derive {Jason.Encoder, only: [:spans, :errors, :usage, :scan, :rejected]}

  @type usage :: %{input_tokens: non_neg_integer(), output_tokens: non_neg_integer()}
  @type scan :: %{String.t() => %{String.t() => float()}}
  @type rejected :: %{String.t() => map()}

  @type t :: %__MODULE__{
          spans: [Span.t()],
          errors: [Error.t()],
          usage: usage() | nil,
          scan: scan() | nil,
          rejected: rejected() | nil
        }

  @enforce_keys [:spans, :errors]
  defstruct [:spans, :errors, usage: nil, scan: nil, rejected: nil]
end
