defmodule Cite.TestRun do
  @moduledoc false

  # A run for testing the pure steps: the given terms, the default options,
  # and a client that fails the test if a pure step ever calls it.

  alias Cite.Policy.Terms
  alias Cite.{Run, Source}

  @spec new(Terms.t(), keyword()) :: Run.t()
  def new(%Terms{} = terms, fields \\ []) do
    struct!(
      Run,
      [
        client: &no_client/1,
        source: Source.new([]),
        terms: terms,
        threshold: 0.5,
        review_band: {0.4, 0.6},
        window: 40,
        max_evidence: 20
      ] ++ fields
    )
  end

  defp no_client(request) do
    raise "a pure step called the client with #{inspect(request)}"
  end
end
