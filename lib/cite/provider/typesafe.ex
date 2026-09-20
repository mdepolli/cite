defmodule Cite.Provider.TypeSafe do
  @moduledoc """
  TypeSafe System One over HTTP (`POST /v1/systemone`).

  Options for `Cite.judge/2`: `:api_key` (or `JEV_API_KEY`; missing raises),
  `:model` (`"jev-1.13.0"`), `:base_url`, and `:req_options`, merged into
  the Req client last — a test passes `plug: {Req.Test, name}`.
  """

  @behaviour Cite.Provider

  @default_model "jev-1.13.0"
  @default_base_url "https://api.typesafe.ai"
  @max_error_body_bytes 2_000

  @type t :: %__MODULE__{http_client: Req.Request.t(), model: String.t()}

  @type error ::
          :unauthorized
          | :server_error
          | {:bad_request, String.t()}
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
        base_url: @default_base_url
      ])

    api_key = opts[:api_key] || System.get_env("JEV_API_KEY")

    if api_key in [nil, ""] do
      raise ArgumentError, "missing API key: pass :api_key or set JEV_API_KEY"
    end

    req_options =
      [
        base_url: opts[:base_url],
        auth: {:bearer, api_key},
        receive_timeout: 120_000,
        retry: :transient,
        redirect: false
      ]
      |> Keyword.merge(opts[:req_options] || [])

    %__MODULE__{http_client: Req.new(req_options), model: opts[:model]}
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

  defp decode({:ok, %Req.Response{status: 200, body: %{} = body}}) do
    {:ok, %{answers: body["answers"] || %{}, usage: usage(body["usage"])}}
  end

  # TypeSafe names the failure in the 400 body; keep that name so the shell
  # can act on it (a window over the request token cap is halved).
  defp decode({:ok, %Req.Response{status: 400, body: %{"detail" => %{"error_type" => type}}}})
       when is_binary(type) do
    {:error, {:bad_request, type}}
  end

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

  defp usage(%{"input_tokens" => input, "output_tokens" => output})
       when is_integer(input) and is_integer(output) do
    %{input_tokens: input, output_tokens: output}
  end

  defp usage(_), do: nil

  defp retry_after_ms(response) do
    with [seconds | _] <- Req.Response.get_header(response, "retry-after"),
         {s, ""} when s >= 0 <- Integer.parse(seconds) do
      s * 1000
    else
      _ -> nil
    end
  end

  # One bounded string per error body, so a huge reply never outlives the
  # Error that records it.
  defp preview(body) when is_binary(body), do: String.slice(body, 0, @max_error_body_bytes)
  defp preview(body), do: body |> inspect() |> String.slice(0, @max_error_body_bytes)
end
