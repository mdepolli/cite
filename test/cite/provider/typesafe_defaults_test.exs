defmodule Cite.Provider.TypeSafeDefaultsTest do
  # Req.default_options/0 is application env, shared by every test that
  # builds a TypeSafe client, so these run apart from them.
  use ExUnit.Case, async: false

  alias Cite.Provider.TypeSafe

  setup do
    defaults = Req.default_options()
    on_exit(fn -> Req.default_options(defaults) end)
  end

  test "refuses a default retry_delay beside the adapter's retry" do
    Req.default_options(retry: :transient, retry_delay: 1)

    assert_raise ArgumentError,
                 ":retry_delay needs a :retry in req_options, because the adapter's retry sets delays itself",
                 fn -> TypeSafe.new(api_key: "k") end
  end

  test "accepts a default retry_delay when req_options brings its own retry" do
    Req.default_options(retry_delay: 1)

    assert %TypeSafe{} = TypeSafe.new(api_key: "k", req_options: [retry: :transient])
  end

  test "accepts a default retry_delay when req_options unsets it" do
    Req.default_options(retry_delay: 1)

    assert %TypeSafe{} = TypeSafe.new(api_key: "k", req_options: [retry_delay: nil])
  end
end
