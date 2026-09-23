defmodule Cite.Run do
  @moduledoc """
  The imperative shell behind `Cite.judge/4`.

  Screens the source in windows, halving a window the provider refuses as
  too large; gathers findings; judges each with one request; assembles the
  `Cite.Report`. Every decision lives in `Cite.Screen`, `Cite.Gather`, and
  `Cite.Judge`, which never see the client. Internal; use `Cite.judge/4`.
  """

  alias Cite.{Answer, Error, Gather, Judge, Passage, Report, Screen, Source}
  alias Cite.Policy.Build

  @spec judge(Cite.client(), Source.t(), module(), keyword()) :: Report.t()
  def judge(client, %Source{} = source, policy_module, opts \\ [])
      when is_function(client, 1) and is_atom(policy_module) do
    opts =
      Keyword.validate!(opts,
        threshold: 0.5,
        review_band: {0.4, 0.6},
        window: 40,
        max_evidence: 20
      )

    threshold = opts[:threshold]
    review_band = opts[:review_band]
    window = opts[:window]
    max_evidence = opts[:max_evidence]

    check_options(threshold, review_band, window, max_evidence)
    policy = Build.read(policy_module)

    screened =
      source.passages
      |> Enum.chunk_every(window)
      |> Enum.flat_map(&screen_window(client, &1, source, policy))
      |> Screen.resolve(policy)

    judged =
      policy
      |> Gather.findings(source, screened.screen,
        threshold: threshold,
        max_evidence: max_evidence
      )
      |> Enum.map(&{&1, call(client, Judge.request(&1, source, policy))})

    %Report{
      findings:
        for(
          {gathered, {:ok, verdict}} <- judged,
          do: Judge.resolve(gathered, verdict.answers, policy, review_band)
        ),
      screen: screened.screen,
      errors:
        screened.errors ++
          for({gathered, {:error, reason}} <- judged, do: finding_error(gathered, reason)),
      usage:
        Report.total_usage(
          screened.usages ++ for({_gathered, {:ok, verdict}} <- judged, do: verdict.usage)
        ),
      models:
        Enum.uniq(
          screened.models ++ for({_gathered, {:ok, %{model: model}}} <- judged, do: model)
        )
    }
  end

  defp check_options(threshold, {low, high}, window, max_evidence)
       when is_number(threshold) and is_number(low) and is_number(high) and low < high and
              is_integer(window) and window > 0 and is_integer(max_evidence) and max_evidence > 0,
       do: :ok

  defp check_options(threshold, review_band, window, max_evidence) do
    raise ArgumentError, """
    invalid options: threshold must be a number, review_band {low, high} with low < high, \
    window and max_evidence positive integers; got \
    #{inspect(threshold: threshold, review_band: review_band, window: window, max_evidence: max_evidence)}
    """
  end

  # A window over the request cap is split in half and both halves screened;
  # only a single passage that still exceeds it is an error. Once one passage
  # alone is too large, its siblings will not fare better, so they are
  # recorded as the same error without a call.
  defp screen_window(client, window, source, policy) do
    case call(client, Screen.request(window, source, policy)) do
      {:error, :request_too_large} when length(window) > 1 ->
        {left, right} = Enum.split(window, div(length(window), 2))
        left_outcomes = screen_window(client, left, source, policy)

        if singleton_too_large?(left_outcomes) do
          left_outcomes ++ [{right, {:error, :request_too_large}}]
        else
          left_outcomes ++ screen_window(client, right, source, policy)
        end

      verdict ->
        [{window, verdict}]
    end
  end

  defp singleton_too_large?(outcomes) do
    Enum.any?(outcomes, &match?({[_one], {:error, :request_too_large}}, &1))
  end

  defp finding_error(%Gather.Finding{concern: concern, passages: passages}, reason) do
    %Error{
      concern: concern.name,
      passage_ids: Enum.map(passages, fn %Passage{id: id} -> id end),
      reason: reason
    }
  end

  # The client is the caller's function; its return is checked here, once,
  # and trusted everywhere after. A reply that skips a question, or answers
  # it in a shape its type cannot have, is not a verdict on it: the whole
  # request becomes an error rather than a "no".
  defp call(client, request) do
    case client.(request) do
      {:ok, %{answers: answers, usage: usage} = fields} = verdict when is_map(answers) ->
        check_usage(usage)
        check_model(Map.get(fields, :model))
        check_answers(request["questions"], answers, verdict)

      {:error, _reason} = error ->
        error

      other ->
        raise ArgumentError, """
        client must return {:ok, %{answers: map, usage: map | nil}} or {:error, reason}, \
        got: #{inspect(other)}
        """
    end
  end

  defp check_answers(questions, answers, verdict) do
    missing = Map.keys(questions) -- Map.keys(answers)

    malformed =
      for {key, question} <- questions,
          Map.has_key?(answers, key),
          not Answer.well_formed?(question["type"], answers[key]),
          do: key

    cond do
      missing != [] -> {:error, {:missing_answers, Enum.sort(missing)}}
      malformed != [] -> {:error, {:malformed_answers, Enum.sort(malformed)}}
      true -> verdict
    end
  end

  defp check_usage(nil), do: :ok

  defp check_usage(%{input_tokens: input, output_tokens: output})
       when is_integer(input) and input >= 0 and is_integer(output) and output >= 0,
       do: :ok

  defp check_usage(other) do
    raise ArgumentError,
          "client usage must be nil or %{input_tokens: n, output_tokens: n}, got: #{inspect(other)}"
  end

  defp check_model(nil), do: :ok
  defp check_model(model) when is_binary(model) and model != "", do: :ok

  defp check_model(other) do
    raise ArgumentError,
          "client model must be a non-empty binary when given, got: #{inspect(other)}"
  end
end
