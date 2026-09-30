defmodule Cite.Provider.TypeSafeDefaultsTest do
  # Req.default_options/0 is application env, shared by every test that
  # builds a TypeSafe client, so these run apart from them.
  use ExUnit.Case, async: false

  import Cite.TestTypeSafe, only: [finch_options_sent: 1]

  alias Cite.Provider.TypeSafe

  setup do
    defaults = Req.default_options()
    on_exit(fn -> Req.default_options(defaults) end)
  end

  test "keeps the app's default finch options beneath the wait and the caller's own" do
    Req.default_options(finch: [name: MyApp.Finch, pool_timeout: 5_000])

    assert finch_options_sent([]) == [name: MyApp.Finch, pool_timeout: :infinity]

    assert finch_options_sent(finch: [pool_timeout: 1_000]) == [
             name: MyApp.Finch,
             pool_timeout: 1_000
           ]

    assert finch_options_sent(finch: [name: MyFinch]) == [pool_timeout: :infinity, name: MyFinch]
  end

  # Req reads a finch: list's timeouts over the top-level ones, so a default
  # list's timeouts would beat the adapter's receive_timeout and the caller's.
  test "drops the timeouts from the app's default finch options" do
    Req.default_options(
      finch: [name: MyApp.Finch, receive_timeout: 200, request_timeout: 300, pool_timeout: 400]
    )

    assert finch_options_sent([]) == [name: MyApp.Finch, pool_timeout: :infinity]
  end

  test "refuses app defaults that can't sit beside the adapter's options" do
    for {defaults, message} <- [
          {[connect_options: [timeout: 1_000]],
           ":connect_options can't be combined with the adapter's :finch options; set Finch pool options under finch: instead, such as finch: [conn_opts: ...]"},
          {[finch: MyApp.Finch],
           "finch: in Req.default_options/0 must be a keyword list, such as finch: [name: MyFinch], got: MyApp.Finch"},
          {[retry: :transient, retry_delay: 1],
           ":retry_delay needs a :retry in req_options, because the adapter's retry sets delays itself"}
        ] do
      Req.default_options(defaults)

      assert_raise ArgumentError, message, fn -> TypeSafe.new(api_key: "k") end
    end
  end

  test "accepts a default retry_delay when req_options brings its own retry" do
    Req.default_options(retry_delay: 1)

    assert %TypeSafe{} = TypeSafe.new(api_key: "k", req_options: [retry: :transient])
  end

  test "refuses a default pool name beside the caller's pool options" do
    Req.default_options(finch: [name: MyApp.Finch])

    assert_raise ArgumentError,
                 "finch: can't set pool options beside name: MyApp.Finch, got: [size: 100]; configure the pool when starting MyApp.Finch instead",
                 fn -> TypeSafe.new(api_key: "k", req_options: [finch: [size: 100]]) end
  end
end
