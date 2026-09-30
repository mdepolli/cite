defmodule Cite.Screen do
  @moduledoc """
  Round 1, minus the client call: every detect asked of every passage, a
  window of passages per request, and the replies folded into scores. Pure.
  Internal.
  """

  alias Cite.{Answer, Error, Passage, Run, Source, Wire}
  alias Cite.Policy.{Question, Terms}

  @type outcome :: {[Passage.t()], {:ok, map()} | {:error, term()}}
  @type screen :: %{String.t() => %{atom() => number()}}

  @doc """
  One request: the window under the source's `as`, and every detect asked
  of every passage in it, keyed `"<passage id>:<detect>"`.
  """
  @spec request(Run.t(), [Passage.t()]) :: map()
  def request(%Run{source: %Source{as: as, show: show}} = run, window) do
    questions =
      for %Passage{id: id} <- window,
          {name, question} <- detects(run.terms),
          into: %{},
          do: {key(id, name), Wire.question(question, %{"passage" => Wire.text_path(as, id)}, [])}

    %{"state" => %{as => Wire.passages(window, show)}, "questions" => questions}
  end

  @doc """
  Folds judged windows into the run. It sets `screen`, the scores per
  passage and detect, adds one `Cite.Error` per failed window, and adds each
  reply's usage and model to the run's. A failed window leaves its passages
  without a row.
  """
  @spec resolve(Run.t(), [outcome()]) :: Run.t()
  def resolve(%Run{} = run, outcomes) do
    names = Keyword.keys(detects(run.terms))
    screen = Enum.reduce(outcomes, %{}, &merge(&1, &2, names))
    errors = for {window, {:error, reason}} <- outcomes, do: window_error(window, reason)
    usages = for {_window, {:ok, verdict}} <- outcomes, do: verdict.usage
    models = for {_window, {:ok, %{model: model}}} <- outcomes, do: model

    %{
      run
      | screen: screen,
        errors: run.errors ++ errors,
        usages: run.usages ++ usages,
        models: run.models ++ models
    }
  end

  # The terms' round-1 questions by name: filters, then directly screened
  # concerns (named by concern, asking its detect), then factors.
  defp detects(%Terms{} = terms) do
    concerns =
      for %{detect: %Question{} = detect} = concern <- terms.concerns,
          do: {concern.name, detect}

    terms.filters ++ concerns ++ terms.factors
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
