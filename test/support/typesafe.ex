defmodule Cite.TestTypeSafe do
  @moduledoc false

  import ExUnit.Assertions

  alias Cite.Provider.TypeSafe

  @request %{"state" => %{}, "questions" => %{}}

  # Sends one request through a TypeSafe client built with `req_options`,
  # stopping it at the adapter, and returns the Finch options it carried.
  @spec finch_options_sent(keyword()) :: keyword()
  def finch_options_sent(req_options) do
    test_pid = self()

    adapter = fn request ->
      send(test_pid, {:finch, request.options[:finch]})
      {request, Req.Response.new(status: 200, body: %{"answers" => %{}})}
    end

    client = Cite.client(TypeSafe, api_key: "k", req_options: [adapter: adapter] ++ req_options)

    assert {:ok, _verdict} = client.(@request)
    assert_received {:finch, finch}
    finch
  end
end
