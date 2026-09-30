defmodule Cite.TestTypeSafe do
  @moduledoc false

  import ExUnit.Assertions

  alias Cite.Provider.TypeSafe

  @request %{"state" => %{}, "questions" => %{}}

  # Sends one request through a TypeSafe client built with `req_options`,
  # stopping it at the adapter, and returns the connection options it
  # carried: the ones present among :pool_timeout, :finch, :connect_options.
  @spec options_sent(keyword()) :: map()
  def options_sent(req_options) do
    client =
      Cite.client(TypeSafe, api_key: "k", req_options: [adapter: __MODULE__] ++ req_options)

    assert {:ok, _verdict} = client.(@request)
    assert_received {:options, options}
    options
  end

  # The adapter: Req calls it in the process that sent the request, so the
  # options go back to that process's mailbox.
  @doc false
  @spec run(Req.Request.t()) :: {Req.Request.t(), Req.Response.t()}
  def run(%Req.Request{} = request) do
    send(self(), {:options, Map.take(request.options, [:pool_timeout, :finch, :connect_options])})
    {request, Req.Response.new(status: 200, body: %{"answers" => %{}})}
  end
end
