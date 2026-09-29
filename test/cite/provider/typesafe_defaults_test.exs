defmodule Cite.Provider.TypeSafeDefaultsTest do
  # Req.default_options/0 is application env, shared by every test that
  # builds a TypeSafe client, so these run apart from them.
  use ExUnit.Case, async: false

  alias Cite.Provider.TypeSafe

  setup do
    defaults = Req.default_options()
    on_exit(fn -> Req.default_options(defaults) end)
  end

  test "keeps the app's default finch options beneath the wait and the caller's own" do
    # Arrange
    Req.default_options(finch: [name: MyApp.Finch])

    # Act
    plain = TypeSafe.new(api_key: "k")
    overridden = TypeSafe.new(api_key: "k", req_options: [finch: [name: MyFinch]])

    # Assert
    assert plain.http_client.options.finch == [pool_timeout: :infinity, name: MyApp.Finch]
    assert overridden.http_client.options.finch == [pool_timeout: :infinity, name: MyFinch]
  end

  test "refuses app defaults that can't sit beside the adapter's finch options" do
    for {defaults, message} <- [
          {[connect_options: [timeout: 1_000]],
           "invalid Req.default_options/0: :connect_options can't be combined with the adapter's :finch options; set Finch pool options under finch: instead, such as finch: [conn_opts: ...]"},
          {[finch: MyApp.Finch],
           "invalid Req.default_options/0: finch: must be a keyword list, such as finch: [name: MyFinch], got: MyApp.Finch"}
        ] do
      Req.default_options(defaults)

      assert_raise ArgumentError, message, fn -> TypeSafe.new(api_key: "k") end
    end
  end
end
