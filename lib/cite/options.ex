defmodule Cite.Options do
  @moduledoc false

  # Spark.Options.validate/2 raises FunctionClauseError on a list that is
  # not a keyword list, such as [1, 2], so that is checked first.
  @spec read(term(), Spark.Options.t()) :: keyword()
  def read(opts, schema) do
    if not Keyword.keyword?(opts) do
      raise ArgumentError, "options must be a keyword list, got: #{inspect(opts)}"
    end

    case Spark.Options.validate(opts, schema) do
      {:ok, options} -> options
      {:error, error} -> raise ArgumentError, Exception.message(error)
    end
  end
end
