defmodule Cite.Screen do
  @moduledoc """
  Round 1, minus the client call: every indicator asked of every passage, a
  window of passages per request, and the replies folded into scores. Pure.
  Internal.
  """

  alias Cite.{Answer, Error, Passage, Policy, Source, Wire}
  alias Cite.Policy.Question

  @type outcome :: {[Passage.t()], {:ok, map()} | {:error, term()}}
  @type screen :: %{String.t() => %{atom() => number()}}

  @doc """
  The policy's round-1 questions by name: filters, then directly screened
  concerns (named by concern, asking its indicator), then factors.
  """
  @spec indicators(Policy.t()) :: [{atom(), Question.t()}]
  def indicators(%Policy{} = policy) do
    concerns =
      for %{indicator: %Question{} = indicator} = concern <- policy.concerns,
          do: {concern.name, indicator}

    policy.filters ++ concerns ++ policy.factors
  end

  @doc """
  One request: the window under the source's `as`, and every indicator asked
  of every passage in it, keyed `"<passage id>:<indicator>"`.
  """
  @spec request([Passage.t()], Source.t(), Policy.t()) :: map()
  def request(window, %Source{as: as, show: show}, %Policy{} = policy) do
    questions =
      for %Passage{id: id} <- window, {name, question} <- indicators(policy), into: %{} do
        {key(id, name), Wire.question(question, %{"passage" => "#{as}.#{id}.text"}, [])}
      end

    %{"state" => %{as => Wire.passages(window, show)}, "questions" => questions}
  end

  @doc """
  Folds judged windows into scores per passage and indicator, one
  `Cite.Error` per failed window, and the usage and model of each reply. A
  failed window leaves its passages without a row.
  """
  @spec resolve([outcome()], Policy.t()) :: %{
          screen: screen(),
          errors: [Error.t()],
          usages: [Cite.usage() | nil],
          models: [String.t()]
        }
  def resolve(outcomes, %Policy{} = policy) do
    names = Keyword.keys(indicators(policy))

    %{
      screen: Enum.reduce(outcomes, %{}, &merge(&1, &2, names)),
      errors: for({window, {:error, reason}} <- outcomes, do: window_error(window, reason)),
      usages: for({_window, {:ok, verdict}} <- outcomes, do: verdict.usage),
      models: for({_window, {:ok, %{model: model}}} <- outcomes, do: model)
    }
  end

  defp window_error(window, reason) do
    %Error{concern: nil, passage_ids: Enum.map(window, & &1.id), reason: reason}
  end

  defp merge({_window, {:error, _reason}}, screen, _names), do: screen

  # Each answer is read under the key this module wrote for it; keys are
  # rebuilt, never parsed.
  defp merge({window, {:ok, %{answers: answers}}}, screen, names) do
    Enum.reduce(window, screen, fn %Passage{id: id}, acc ->
      Map.put(acc, id, Map.new(names, &{&1, Answer.noul(answers[key(id, &1)])}))
    end)
  end

  defp key(id, name), do: id <> ":" <> Atom.to_string(name)
end
