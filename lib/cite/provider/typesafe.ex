defmodule Cite.Provider.TypeSafe do
  @moduledoc """
  TypeSafe System One over HTTP (`POST /v1/systemone`).

  Options for `Cite.client/2`: `:api_key` (or `JEV_API_KEY`; missing raises),
  `:model` (`"jev-1.13.0"`), `:base_url`, `:max_retry_delay` (ms, 30 000 —
  the cap on any one retry wait, `Retry-After` included), and
  `:req_options`, merged into the Req client last — a test passes
  `plug: {Req.Test, name}`.
  """

  @behaviour Cite.Provider

  # The model the vulnerability benchmark's questions and criteria were tuned
  # against; a newer Jev may read the same wording differently.
  @default_model "jev-1.13.0"
  @default_base_url "https://api.typesafe.ai"
  @max_error_body_bytes 2_000
  @max_retries 3
  @max_retry_delay_ms :timer.seconds(30)

  @type t :: %__MODULE__{http_client: Req.Request.t(), model: String.t()}

  @type error ::
          :request_too_large
          | :unauthorized
          | :server_error
          | {:bad_request, String.t()}
          | {:malformed_reply, String.t()}
          | {:rate_limited, non_neg_integer() | nil}
          | {:api_error, pos_integer(), String.t()}
          | {:request_error, Exception.t()}

  @derive {Inspect, except: [:http_client]}
  @enforce_keys [:http_client, :model]
  defstruct [:http_client, :model]

  @impl Cite.Provider
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    opts =
      Keyword.validate!(opts, [
        :api_key,
        :req_options,
        model: @default_model,
        base_url: @default_base_url,
        max_retry_delay: @max_retry_delay_ms
      ])

    api_key = opts[:api_key] || System.get_env("JEV_API_KEY")
    model = opts[:model]
    base_url = opts[:base_url]
    max_retry_delay = opts[:max_retry_delay]
    req_overrides = opts[:req_options] || []

    if api_key in [nil, ""] do
      raise ArgumentError, "missing API key: pass :api_key or set JEV_API_KEY"
    end

    unless is_integer(max_retry_delay) and max_retry_delay >= 0 do
      raise ArgumentError,
            "max_retry_delay must be a non-negative integer (ms), got: #{inspect(max_retry_delay)}"
    end

    # Req forbids :retry_delay next to a retry function that returns its own
    # delays; better to say so here than inside the first call.
    if Keyword.has_key?(req_overrides, :retry_delay) and
         not Keyword.has_key?(req_overrides, :retry) do
      raise ArgumentError,
            "req_options :retry_delay needs its own :retry; the adapter's retry sets delays itself"
    end

    req_options =
      [
        base_url: base_url,
        auth: {:bearer, api_key},
        receive_timeout: 120_000,
        retry: &retry/2,
        max_retries: @max_retries,
        redirect: false
      ]
      |> Keyword.merge(req_overrides)

    http_client =
      req_options
      |> Req.new()
      |> Req.Request.put_private(:cite_max_retry_delay, max_retry_delay)

    %__MODULE__{http_client: http_client, model: model}
  end

  @impl Cite.Provider
  @spec judge(t(), map()) :: {:ok, Cite.verdict()} | {:error, error()}
  def judge(%__MODULE__{http_client: req, model: model}, %{
        "state" => state,
        "questions" => questions
      }) do
    req
    |> Req.post(
      url: "/v1/systemone",
      json: %{"model" => model, "state" => state, "questions" => questions}
    )
    |> decode()
  end

  # Req owns retries: 429, 529 and 5xx (TypeSafe documents 529 as transient,
  # Req's :transient list does not include it) and connection failures, at
  # most @max_retries times with a delay capped at :max_retry_delay (30 s) even
  # when Retry-After says longer. A timeout is not retried: a 120 s call
  # retried is eight minutes, and a slow success would be billed twice. What
  # reaches decode/1 has already had its retries; a 429 there still carries
  # Retry-After so the caller knows what the server asked for.
  defp retry(request, %Req.Response{status: status} = response)
       when status == 429 or status == 529 or status in 500..504 do
    {:delay, min(retry_after_ms(response) || backoff_ms(request), max_retry_delay(request))}
  end

  defp retry(request, %Req.TransportError{reason: reason}) when reason != :timeout do
    {:delay, min(backoff_ms(request), max_retry_delay(request))}
  end

  defp retry(_request, _response_or_exception), do: false

  defp max_retry_delay(request) do
    Req.Request.get_private(request, :cite_max_retry_delay, @max_retry_delay_ms)
  end

  defp backoff_ms(request) do
    Integer.pow(2, Req.Request.get_private(request, :req_retry_count, 0)) * 1_000
  end

  defp decode({:ok, %Req.Response{status: 200, body: %{"answers" => answers} = body}})
       when is_map(answers) do
    verdict = %{answers: answers, usage: usage(body["usage"])}

    case body["model"] do
      model when is_binary(model) and model != "" -> {:ok, Map.put(verdict, :model, model)}
      _ -> {:ok, verdict}
    end
  end

  # A 200 Cite cannot read is a network fact, not a verdict of "no" everywhere.
  defp decode({:ok, %Req.Response{status: 200, body: body}}) do
    {:error, {:malformed_reply, preview(body)}}
  end

  # TypeSafe names the failure in the 400 body. Its token cap is the
  # provider-neutral :request_too_large the pipeline halves windows on;
  # other names pass through as-is. The "max_tokens_exceeded" name is not in
  # TypeSafe's published docs: it is what the API returned on oversized
  # windows during the prototype, and the halving behaviour was built on it.
  # The docs list validation failures as 422; the prototype saw 400. Both
  # are matched by the error type so a status change does not lose halving.
  defp decode({:ok, %Req.Response{status: status, body: %{"detail" => %{"error_type" => type}}}})
       when status in [400, 422] and type == "max_tokens_exceeded",
       do: {:error, :request_too_large}

  defp decode({:ok, %Req.Response{status: status, body: %{"detail" => %{"error_type" => type}}}})
       when status in [400, 422] and is_binary(type),
       do: {:error, {:bad_request, type}}

  defp decode({:ok, %Req.Response{status: 400, body: body}}),
    do: {:error, {:bad_request, preview(body)}}

  defp decode({:ok, %Req.Response{status: 401}}), do: {:error, :unauthorized}

  defp decode({:ok, %Req.Response{status: 429} = response}) do
    {:error, {:rate_limited, retry_after_ms(response)}}
  end

  defp decode({:ok, %Req.Response{status: status}}) when status >= 500,
    do: {:error, :server_error}

  defp decode({:ok, %Req.Response{status: status, body: body}}) do
    {:error, {:api_error, status, preview(body)}}
  end

  defp decode({:error, exception}), do: {:error, {:request_error, exception}}

  # A count the shell would refuse (negative, non-integer) is the network's
  # doing, not the caller's: report no usage rather than raise.
  defp usage(%{"input_tokens" => input, "output_tokens" => output})
       when is_integer(input) and input >= 0 and is_integer(output) and output >= 0 do
    %{input_tokens: input, output_tokens: output}
  end

  defp usage(_), do: nil

  # Retry-After is delay-seconds or an HTTP date; anything else, or a negative
  # value, reads as no advice. Req.Response.get_retry_after/1 raises on the
  # unparseable case, and a proxy's 429 can carry one.
  defp retry_after_ms(response) do
    case Req.Response.get_header(response, "retry-after") do
      [value | _] -> retry_after_ms_from(value)
      [] -> nil
    end
  end

  defp retry_after_ms_from(value) do
    case Integer.parse(value) do
      {seconds, ""} when seconds >= 0 -> seconds * 1000
      {_negative, ""} -> nil
      :error -> http_date_ms(value)
      _ -> nil
    end
  end

  defp http_date_ms(value) do
    case Req.Utils.parse_http_date(value) do
      {:ok, date} -> max(DateTime.diff(date, DateTime.utc_now(), :millisecond), 0)
      _ -> nil
    end
  end

  # One bounded string per error body, so a huge reply never outlives the
  # Error that records it.
  defp preview(body) when is_binary(body), do: String.slice(body, 0, @max_error_body_bytes)

  defp preview(body) do
    body
    |> inspect()
    |> String.slice(0, @max_error_body_bytes)
  end
end
