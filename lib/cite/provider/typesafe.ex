defmodule Cite.Provider.TypeSafe do
  # The Jev release Cite's behaviour was measured against; a newer Jev may
  # read the same wording differently.
  @default_model "jev-1.13.0"
  @default_base_url "https://api.typesafe.ai"
  @max_error_body_bytes 2_000
  @max_retries 3
  @max_retry_delay_ms :timer.seconds(30)

  @schema Spark.Options.new!(
            api_key: [
              type: {:custom, __MODULE__, :validate_api_key, []},
              required: true,
              doc: "The TypeSafe API key."
            ],
            model: [
              type: :string,
              default: @default_model,
              doc: "The Jev model that answers."
            ],
            base_url: [
              type: :string,
              default: @default_base_url,
              doc: "The API's base URL."
            ],
            max_retry_delay: [
              type: :non_neg_integer,
              default: @max_retry_delay_ms,
              doc: "Milliseconds: the cap on any one retry wait, `Retry-After` included."
            ],
            req_options: [
              type: {:custom, __MODULE__, :validate_req_options, []},
              default: [],
              doc: """
              Req options, merged over the ones the adapter sets, as `Req.new/1` \
              merges them; the app's `Req.default_options/0` sits beneath both. \
              See "Req options" below.\
              """
            ]
          )

  @moduledoc """
  TypeSafe System One over HTTP (`POST /v1/systemone`).

  ## Options

  For `Cite.client/2`:

  #{Spark.Options.docs(@schema)}

  ## Retries

  Rate limits (429), overloads (529), server errors (500–504), and connection
  failures are retried up to three times, honouring `Retry-After`, with any one
  wait capped at `max_retry_delay` (30 seconds by default). Timeouts are not
  retried: a 120-second call retried is eight minutes, and a slow success would
  be billed twice.

  ## Req options

  The adapter builds its Req client with these options. Anything in
  `req_options` overrides them, key by key, as `Req.new/1` merges; the
  app's `Req.default_options/0` applies beneath both.

  | Option | Set to | To change it |
  | --- | --- | --- |
  | `base_url` | the `base_url` option | use `base_url` |
  | `auth` | `{:bearer, api_key}` | use `api_key` |
  | `receive_timeout` | `120_000` | `req_options: [receive_timeout: ms]` |
  | `retry` | the adapter's retry, above | `req_options: [retry: ...]`, which replaces it |
  | `max_retries` | `3` | `req_options: [max_retries: n]` |
  | `redirect` | `false` | `req_options: [redirect: true]` |
  | `pool_timeout` | `:infinity`, unless set | `req_options: [finch: [pool_timeout: ms]]` |

  Every other Req option passes through as Req documents it. The common
  ones:

  - Tests: `req_options: [plug: {Req.Test, MyApp.TypeSafeStub}]`.
  - A larger connection pool: `req_options: [finch: [size: 100]]`, which Req
    starts and supervises, or `finch: [name: MyFinch]` for a Finch you run.
  - A proxy, custom CA certificates, or HTTP/2: `connect_options: [...]`.

  One combination is refused when the client is built, where Req would
  raise only on the first retry: a `:retry_delay`, in `req_options` or the
  app's defaults, without a `:retry` in `req_options`. The adapter's retry
  sets its own delays.

  ## Connections

  Requests go through Req's default Finch pool, 50 connections per host.
  Past that, a request waits for a connection with no time limit, so
  `concurrency` above 50 queues inside Finch instead of sending more at
  once. A `pool_timeout` under `finch:`, in `req_options` or the app's
  defaults, sets a limit instead.

  ## The size cap

  A request over the model's token cap comes back as a 400 whose body names
  the failure: `{"detail": {"error_type": "max_tokens_exceeded"}}`. This
  provider reports it as `:request_too_large`, the error on which
  `Cite.judge/4` halves round-1 windows. That name is observed behaviour,
  checked against the live API on 2026-09-26; TypeSafe's docs do not list
  it. If TypeSafe renames it, oversized windows will be recorded as bad
  requests instead of halved.
  """

  @behaviour Cite.Provider

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
  def new(opts) do
    opts = options(opts)
    api_key = opts[:api_key]
    model = opts[:model]
    base_url = opts[:base_url]
    max_retry_delay = opts[:max_retry_delay]
    req_overrides = opts[:req_options]
    adapter_retry = &retry/2

    # A request past the pool's size waits its turn instead of raising: the
    # wait restarts at every checkout and the pool is shared node-wide, so
    # any finite limit is eventually reached under load. It's set on the
    # request, not in a finch: list, so every connection option stays Req's
    # to merge; a pool_timeout under finch:, anyone's, still takes precedence.
    http_client =
      [
        base_url: base_url,
        auth: {:bearer, api_key},
        receive_timeout: 120_000,
        retry: adapter_retry,
        max_retries: @max_retries,
        redirect: false
      ]
      |> Keyword.merge(req_overrides)
      |> Req.new()
      |> Req.Request.put_new_option(:pool_timeout, :infinity)
      |> Req.Request.put_private(:cite_max_retry_delay, max_retry_delay)

    check_retry_delay(http_client, adapter_retry)

    %__MODULE__{http_client: http_client, model: model}
  end

  # Req refuses a :retry_delay beside a retry function that sets its own
  # delays, as the adapter's does, but only on the first retry. So it's
  # checked here, on the options Req built: the delay may come from
  # req_options or the app's Req.default_options/0. A nil one is unset.
  defp check_retry_delay(%Req.Request{options: options}, adapter_retry) do
    if options[:retry_delay] && options[:retry] == adapter_retry do
      raise ArgumentError,
            ":retry_delay needs a :retry in req_options, because the adapter's retry sets delays itself"
    end
  end

  defp options(opts) do
    case Spark.Options.validate(opts, @schema) do
      {:ok, options} -> options
      {:error, error} -> raise ArgumentError, Exception.message(error)
    end
  end

  @doc false
  def validate_api_key(key) when is_binary(key) and key != "", do: {:ok, key}
  def validate_api_key(key), do: {:error, "expected a non-empty string, got: #{inspect(key)}"}

  @doc false
  def validate_req_options(req_options) do
    if Keyword.keyword?(req_options),
      do: {:ok, req_options},
      else: {:error, "expected a keyword list, got: #{inspect(req_options)}"}
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
  # TypeSafe's published docs: it is what the live API returns on an
  # oversized request (see "The size cap" in the moduledoc). The docs list
  # validation failures as 422; the API answers 400. Both are matched by the
  # error type so a status change does not lose halving.
  defp decode({:ok, %Req.Response{status: status, body: %{"detail" => %{"error_type" => type}}}})
       when status in [400, 422] and type == "max_tokens_exceeded",
       do: {:error, :request_too_large}

  defp decode({:ok, %Req.Response{status: status, body: %{"detail" => %{"error_type" => type}}}})
       when status in [400, 422] and is_binary(type),
       do: {:error, {:bad_request, type}}

  defp decode({:ok, %Req.Response{status: status, body: body}}) when status in [400, 422],
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
