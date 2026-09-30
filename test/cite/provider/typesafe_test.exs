defmodule Cite.Provider.TypeSafeTest do
  use ExUnit.Case, async: true

  import Cite.TestTypeSafe, only: [options_sent: 1]

  alias Cite.Provider.TypeSafe
  alias Cite.Report
  alias Cite.TestPolicies.Riddles
  alias Req.{Request, TransportError}

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
      for {opts, message} <- [
            {[], ~r/required :api_key option not found/},
            {[api_key: ""], ~r/invalid value for :api_key option: expected a non-empty string/}
          ] do
        assert_raise ArgumentError, message, fn -> TypeSafe.new(opts) end
      end
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
                   ":retry_delay needs a :retry in req_options, because the adapter's retry sets delays itself",
                   fn ->
                     TypeSafe.new(api_key: "k", req_options: [retry_delay: fn _ -> 0 end])
                   end
    end

    test "refuses req_options that are not a keyword list" do
      assert_raise ArgumentError,
                   "invalid value for :req_options option: expected keyword list, got: :nope",
                   fn -> TypeSafe.new(api_key: "k", req_options: :nope) end
    end

    test "hides the http client from inspect" do
      refute inspect(TypeSafe.new(api_key: "k")) =~ "http_client"
    end

    test "raises on options that are not a keyword list" do
      for {opts, message} <- [
            {[1, 2], "options must be a keyword list, got: [1, 2]"},
            {%{api_key: "k"}, ~s(options must be a keyword list, got: %{api_key: "k"})}
          ] do
        assert_raise ArgumentError, message, fn -> TypeSafe.new(opts) end
      end
    end

    test "rejects unknown options" do
      assert_raise ArgumentError, ~r/unknown options \[:modle\]/, fn ->
        TypeSafe.new(api_key: "k", modle: "x")
      end
    end

    test "waits for a pooled connection with no time limit, and sets no finch: list" do
      assert options_sent([]) == %{pool_timeout: :infinity}
    end

    test "leaves a caller's finch: to Req" do
      assert options_sent(finch: [name: MyFinch]) == %{
               pool_timeout: :infinity,
               finch: [name: MyFinch]
             }
    end

    test "leaves a caller's connect_options to Req" do
      assert options_sent(connect_options: [timeout: 1_000]) == %{
               pool_timeout: :infinity,
               connect_options: [timeout: 1_000]
             }
    end

    # Only Req's Finch adapter refuses the pair; this test's adapter is not it.
    test "leaves connect_options beside finch: to Req and its adapter" do
      assert options_sent(finch: [size: 1], connect_options: [timeout: 1_000]) == %{
               pool_timeout: :infinity,
               finch: [size: 1],
               connect_options: [timeout: 1_000]
             }
    end

    test "treats a nil retry_delay as unset, as Req does" do
      assert %TypeSafe{} = TypeSafe.new(api_key: "k", req_options: [retry_delay: nil])
    end
  end

  describe "judge/2 request" do
    test "posts model, state, and questions with a bearer token" do
      # Arrange
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.host == "api.typesafe.ai"
        assert conn.request_path == "/v1/systemone"
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer k"]

        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert Jason.decode!(body) == %{
                 "model" => "jev-test",
                 "state" => %{"passages" => %{"U0" => %{"text" => "hi"}}},
                 "questions" => %{"U0:d" => %{"type" => "noul"}}
               }

        Req.Test.json(conn, %{"answers" => %{}})
      end)

      # Act + Assert
      assert {:ok, _} = judge(model: "jev-test").(@request)
    end

    test "sends jev-1.13.0 when no model is given" do
      # Arrange
      Req.Test.expect(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body)["model"] == "jev-1.13.0"

        Req.Test.json(conn, %{"answers" => %{}})
      end)

      # Act + Assert
      assert {:ok, _} = judge().(@request)
    end
  end

  describe "judge/2 replies" do
    test "returns answers, usage, and the model that answered on 200" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{
          "model" => "jev-1.13.0",
          "answers" => %{"U0:d" => %{"noul" => 0.8}},
          "usage" => %{"input_tokens" => 12, "output_tokens" => 0}
        })
      end)

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

    test "usage is nil when the reply reports a count the shell would refuse" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{
          "answers" => %{},
          "usage" => %{"input_tokens" => -1, "output_tokens" => 0}
        })
      end)

      assert judge().(@request) == {:ok, %{answers: %{}, usage: nil}}
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
      Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, 418, String.duplicate("x", 5_000)))
      {:error, {:api_error, 418, preview}} = judge().(@request)

      assert String.length(preview) == 2_000
    end

    test "wraps transport failures" do
      Req.Test.stub(__MODULE__, &Req.Test.transport_error(&1, :econnrefused))

      assert {:error, {:request_error, %TransportError{reason: :econnrefused}}} =
               judge().(@request)
    end

    # The plug tests never reach Finch; this one sends through the real
    # adapter, with the connection options callers pass.
    test "reaches Finch without a plug and reports a refused connection as an error" do
      for req_options <- [[], [connect_options: [timeout: 1_000]], [finch: [size: 3]]] do
        client =
          Cite.client(TypeSafe,
            api_key: "k",
            base_url: "http://127.0.0.1:1",
            req_options: [retry: false] ++ req_options
          )

        assert {:error, {:request_error, %TransportError{reason: :econnrefused}}} =
                 client.(@request)
      end
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

    test "honours Retry-After, capped at max_retry_delay: a minute asked, none waited" do
      calls = stub_failing_once(&send_with_retry_after(&1, 429, "60"))
      {elapsed_us, reply} = :timer.tc(fn -> retrying_judge(max_retry_delay: 0).(@request) end)

      assert {match?({:ok, _}, reply), Agent.get(calls, & &1), elapsed_us < 500_000} ==
               {true, 2, true}
    end

    test "retries when Retry-After is missing, unparseable, negative, or fractional" do
      for {status, retry_after} <- [{503, nil}, {429, "soon"}, {503, "-1"}, {503, "7.5"}] do
        # Arrange
        calls = stub_failing_once(&send_with_retry_after(&1, status, retry_after))

        # Act + Assert
        assert {:ok, _} = retrying_judge(max_retry_delay: 0).(@request)
        assert Agent.get(calls, & &1) == 2
      end
    end

    test "retries on an HTTP-date Retry-After" do
      # Arrange
      calls = stub_failing_once(&send_with_retry_after(&1, 429, "Thu, 01 Jan 2015 00:00:00 GMT"))

      # Act + Assert
      assert {:ok, _} = retrying_judge().(@request)
      assert Agent.get(calls, & &1) == 2
    end

    test "backs off by the retry count Req keeps in the private :req_retry_count" do
      # The backoff reads a private Req field; if Req renames it, every
      # attempt reads :unset here and the backoff silently stops growing.
      {:ok, calls} = Agent.start_link(fn -> 0 end)
      test_pid = self()

      Req.Test.stub(__MODULE__, fn conn ->
        if Agent.get_and_update(calls, &{&1, &1 + 1}) < 2,
          do: Plug.Conn.send_resp(conn, 503, ""),
          else: Req.Test.json(conn, %{"answers" => %{}})
      end)

      record = fn request ->
        send(test_pid, {:attempt, Request.get_private(request, :req_retry_count, :unset)})
        request
      end

      client =
        TypeSafe.new(
          api_key: "k",
          max_retry_delay: 0,
          req_options: [plug: {Req.Test, __MODULE__}, retry_log_level: false]
        )

      client = %{
        client
        | http_client: Request.append_request_steps(client.http_client, record: record)
      }

      reply = TypeSafe.judge(client, @request)

      attempts =
        for _ <- 1..3 do
          receive do
            {:attempt, count} -> count
          after
            0 -> :none
          end
        end

      assert {match?({:ok, _}, reply), attempts} == {true, [:unset, 1, 2]}
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
      assert {:error, {:request_error, %TransportError{reason: :timeout}}} =
               retrying_judge().(@request)

      assert Agent.get(calls, & &1) == 1
    end
  end

  describe "through Cite.judge/4" do
    # The moduledoc suggests a Req.Test plug for tests. judge/4 sends each
    # request from a task, so the stub this test process owns must still
    # answer there.
    test "answers from a Req.Test stub the caller owns" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{
          "model" => "jev-stub",
          "answers" => %{"P000:riddle" => %{"noul" => 0.1}}
        })
      end)

      assert %Report{errors: [], models: ["jev-stub"]} =
               Cite.judge(judge(), Cite.source(["a"]), Riddles)
    end
  end
end
