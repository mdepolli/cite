defmodule Cite.Provider.TypeSafeTest do
  # Not async: new/1 tests clear JEV_API_KEY, which is process-global.
  use ExUnit.Case, async: false

  alias Cite.Provider.TypeSafe

  @request %{
    "state" => %{"passages" => %{"U0" => %{"text" => "hi"}}},
    "questions" => %{"U0:d" => %{"type" => "noul"}}
  }

  defp judge(opts \\ []) do
    Cite.client(
      TypeSafe,
      [api_key: "k", req_options: [plug: {Req.Test, __MODULE__}, retry: false]] ++ opts
    )
  end

  # The adapter's own retry policy; the stubs send Retry-After: 0 to keep it fast.
  defp retrying_judge(opts \\ []) do
    Cite.client(
      TypeSafe,
      [api_key: "k", req_options: [plug: {Req.Test, __MODULE__}, retry_log_level: false]] ++ opts
    )
  end

  # Answers the first attempt with `first`, every later one with an empty
  # reply, and counts the attempts.
  defp stub_failing_once(first) do
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    Req.Test.stub(__MODULE__, fn conn ->
      if Agent.get_and_update(calls, &{&1, &1 + 1}) == 0,
        do: first.(conn),
        else: Req.Test.json(conn, %{"answers" => %{}})
    end)

    calls
  end

  defp send_with_retry_after(conn, status, nil), do: Plug.Conn.send_resp(conn, status, "")

  defp send_with_retry_after(conn, status, retry_after) do
    conn
    |> Plug.Conn.put_resp_header("retry-after", retry_after)
    |> Plug.Conn.send_resp(status, "")
  end

  describe "new/1" do
    test "raises without an api key" do
      System.delete_env("JEV_API_KEY")

      assert_raise ArgumentError, ~r/missing API key/, fn -> TypeSafe.new() end
      assert_raise ArgumentError, ~r/missing API key/, fn -> TypeSafe.new(api_key: "") end
    end

    test "refuses a max_retry_delay that would not cap anything" do
      for {bad, message} <- [
            {nil,
             "invalid value for :max_retry_delay option: expected non negative integer, got: nil"},
            {"30000",
             ~s(invalid value for :max_retry_delay option: expected non negative integer, got: "30000")},
            {-1,
             "invalid value for :max_retry_delay option: expected non negative integer, got: -1"}
          ] do
        assert_raise ArgumentError, message, fn ->
          TypeSafe.new(api_key: "k", max_retry_delay: bad)
        end
      end
    end

    test "refuses retry_delay without a retry of its own" do
      assert_raise ArgumentError,
                   "invalid value for :req_options option: :retry_delay needs its own :retry; the adapter's retry sets delays itself",
                   fn ->
                     TypeSafe.new(api_key: "k", req_options: [retry_delay: fn _ -> 0 end])
                   end
    end

    test "refuses req_options that are not a keyword list" do
      assert_raise ArgumentError,
                   "invalid value for :req_options option: expected a keyword list, got: :nope",
                   fn -> TypeSafe.new(api_key: "k", req_options: :nope) end
    end

    test "hides the http client from inspect" do
      refute inspect(TypeSafe.new(api_key: "k")) =~ "http_client"
    end

    test "rejects unknown options" do
      assert_raise ArgumentError, ~r/unknown options \[:modle\]/, fn ->
        TypeSafe.new(api_key: "k", modle: "x")
      end
    end
  end

  describe "judge/2 request" do
    test "posts model, state, and questions with a bearer token" do
      # Arrange
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/v1/systemone"
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer k"]

        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert Jason.decode!(body) == %{
                 "model" => "jev-test",
                 "state" => @request["state"],
                 "questions" => @request["questions"]
               }

        Req.Test.json(conn, %{"answers" => %{}})
      end)

      # Act + Assert
      assert {:ok, _} = judge(model: "jev-test").(@request)
    end
  end

  describe "judge/2 replies" do
    test "returns answers, usage, and the model that answered on 200" do
      # Arrange
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{
          "model" => "jev-1.13.0",
          "answers" => %{"U0:d" => %{"noul" => 0.8}},
          "usage" => %{"input_tokens" => 12, "output_tokens" => 0}
        })
      end)

      # Act + Assert
      assert judge().(@request) ==
               {:ok,
                %{
                  answers: %{"U0:d" => %{"noul" => 0.8}},
                  usage: %{input_tokens: 12, output_tokens: 0},
                  model: "jev-1.13.0"
                }}
    end

    test "omits model when the reply does not name one" do
      Req.Test.stub(__MODULE__, &Req.Test.json(&1, %{"answers" => %{}}))

      assert judge().(@request) == {:ok, %{answers: %{}, usage: nil}}
    end

    test "usage is nil when the reply omits it or reports a count the shell would refuse" do
      for body <- [
            %{"answers" => %{}},
            %{"answers" => %{}, "usage" => %{"input_tokens" => -1, "output_tokens" => 0}}
          ] do
        Req.Test.stub(__MODULE__, &Req.Test.json(&1, body))

        assert judge().(@request) == {:ok, %{answers: %{}, usage: nil}}
      end
    end

    test "maps the token cap to :request_too_large on 400 and 422, keeps other names" do
      for {status, type, expected} <- [
            {400, "max_tokens_exceeded", :request_too_large},
            {422, "max_tokens_exceeded", :request_too_large},
            {400, "invalid_question", {:bad_request, "invalid_question"}}
          ] do
        Req.Test.stub(__MODULE__, fn conn ->
          conn
          |> Plug.Conn.put_status(status)
          |> Req.Test.json(%{"detail" => %{"error_type" => type}})
        end)

        assert judge().(@request) == {:error, expected}
      end
    end

    test "a 400 or 422 without TypeSafe's detail carries the body preview" do
      for status <- [400, 422] do
        Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, status, "nope"))

        assert judge().(@request) == {:error, {:bad_request, "nope"}}
      end
    end

    test "a 200 without a map of answers is a malformed reply, not a verdict" do
      for body <- [%{"ok" => true}, %{"answers" => []}] do
        Req.Test.stub(__MODULE__, &Req.Test.json(&1, body))

        assert {:error, {:malformed_reply, _}} = judge().(@request)
      end
    end

    test "maps 401, 429 with retry-after, and 5xx" do
      for {status, retry_after, expected} <- [
            {401, nil, :unauthorized},
            {429, "7", {:rate_limited, 7000}},
            {429, "soon", {:rate_limited, nil}},
            {503, nil, :server_error}
          ] do
        Req.Test.stub(__MODULE__, &send_with_retry_after(&1, status, retry_after))

        assert judge().(@request) == {:error, expected}
      end
    end

    test "bounds an unexpected error body" do
      # Arrange
      Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, 418, String.duplicate("x", 5_000)))

      # Act
      {:error, {:api_error, 418, preview}} = judge().(@request)

      # Assert
      assert String.length(preview) == 2_000
    end

    test "wraps transport failures" do
      Req.Test.stub(__MODULE__, &Req.Test.transport_error(&1, :econnrefused))

      assert {:error, {:request_error, %Req.TransportError{reason: :econnrefused}}} =
               judge().(@request)
    end
  end

  describe "judge/2 retries" do
    test "retries 529 and 429 with Retry-After, then succeeds" do
      for status <- [529, 429] do
        # Arrange
        calls = stub_failing_once(&send_with_retry_after(&1, status, "0"))

        # Act + Assert
        assert {:ok, _} = retrying_judge().(@request)
        assert Agent.get(calls, & &1) == 2
      end
    end

    test "gives up after the retries and reports the last 429" do
      # Arrange
      {:ok, calls} = Agent.start_link(fn -> 0 end)

      Req.Test.stub(__MODULE__, fn conn ->
        Agent.update(calls, &(&1 + 1))
        send_with_retry_after(conn, 429, "0")
      end)

      # Act + Assert
      assert retrying_judge().(@request) == {:error, {:rate_limited, 0}}
      assert Agent.get(calls, & &1) == 4
    end

    test "falls back to backoff when Retry-After is missing, unparseable, negative, or fractional" do
      for {status, retry_after} <- [{503, nil}, {429, "soon"}, {503, "-1"}, {503, "7.5"}] do
        # Arrange
        calls = stub_failing_once(&send_with_retry_after(&1, status, retry_after))

        # Act + Assert
        assert {:ok, _} = retrying_judge(max_retry_delay: 0).(@request)
        assert Agent.get(calls, & &1) == 2
      end
    end

    test "an HTTP-date Retry-After already past waits no longer" do
      # Arrange
      calls = stub_failing_once(&send_with_retry_after(&1, 429, "Thu, 01 Jan 2015 00:00:00 GMT"))

      # Act + Assert
      assert {:ok, _} = retrying_judge().(@request)
      assert Agent.get(calls, & &1) == 2
    end

    test "retries a connection failure, then succeeds" do
      # Arrange
      calls = stub_failing_once(&Req.Test.transport_error(&1, :econnrefused))

      # Act + Assert
      assert {:ok, _} = retrying_judge(max_retry_delay: 0).(@request)
      assert Agent.get(calls, & &1) == 2
    end

    test "does not retry a timeout" do
      # Arrange
      {:ok, calls} = Agent.start_link(fn -> 0 end)

      Req.Test.stub(__MODULE__, fn conn ->
        Agent.update(calls, &(&1 + 1))
        Req.Test.transport_error(conn, :timeout)
      end)

      # Act + Assert
      assert {:error, {:request_error, %Req.TransportError{reason: :timeout}}} =
               retrying_judge().(@request)

      assert Agent.get(calls, & &1) == 1
    end
  end
end
