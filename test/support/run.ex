defmodule Cite.TestRun do
  @moduledoc false

  # A run for testing the pure steps: the given terms, the default options,
  # and a client that fails the test if a pure step ever calls it.

  alias Cite.Policy.Terms
  alias Cite.{Run, Source}
  alias Cite.TestPolicies.Riddles

  # Run.new/4 supplies the default options; its policy's terms give way to
  # the ones given.
  @spec new(Terms.t(), keyword()) :: Run.t()
  def new(%Terms{} = terms, fields \\ []) do
    run = Run.new(&no_client/1, Source.new([]), Riddles, [])

    struct!(run, [terms: terms] ++ fields)
  end

  defp no_client(request) do
    raise "a pure step called the client with #{inspect(request)}"
  end
end
