defmodule Cite.Provider.TypeSafeDefaultsTest do
  # Req.default_options/0 is application env, shared by every test that
  # builds a TypeSafe client, so these run apart from them.
  use ExUnit.Case, async: false

  import Cite.TestTypeSafe, only: [options_sent: 1]

  alias Cite.Provider.TypeSafe

  setup do
    defaults = Req.default_options()
    on_exit(fn -> Req.default_options(defaults) end)
  end

  test "leaves the app's default finch: to Req" do
    Req.default_options(finch: [name: MyApp.Finch])

    assert options_sent([]) == %{pool_timeout: :infinity, finch: [name: MyApp.Finch]}
  end

  test "leaves the app's default connect_options to Req" do
    Req.default_options(connect_options: [timeout: 1_000])

    assert options_sent([]) == %{pool_timeout: :infinity, connect_options: [timeout: 1_000]}
  end

  test "refuses a caller's finch: beside the app's default connect_options" do
    Req.default_options(connect_options: [timeout: 1_000])

    assert_raise ArgumentError,
                 ":connect_options can't be combined with :finch, in req_options or Req.default_options/0; set them as Finch pool options instead",
                 fn -> TypeSafe.new(api_key: "k", req_options: [finch: [size: 100]]) end
  end

  test "lets a caller's finch: replace the app's default one whole, as Req does" do
    Req.default_options(finch: [name: MyApp.Finch])

    assert options_sent(finch: [size: 100]) == %{pool_timeout: :infinity, finch: [size: 100]}
  end

  test "refuses a default retry_delay beside the adapter's retry" do
    Req.default_options(retry: :transient, retry_delay: 1)

    assert_raise ArgumentError,
                 ":retry_delay needs a :retry in req_options, because the adapter's retry sets delays itself",
                 fn -> TypeSafe.new(api_key: "k") end
  end

  test "accepts a default retry_delay when req_options brings its own retry or unsets it" do
    Req.default_options(retry_delay: 1)

    assert %TypeSafe{} = TypeSafe.new(api_key: "k", req_options: [retry: :transient])
    assert %TypeSafe{} = TypeSafe.new(api_key: "k", req_options: [retry_delay: nil])
  end
end
