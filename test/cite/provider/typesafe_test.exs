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

  describe "new/1" do
    test "raises without an api key" do
      System.delete_env("JEV_API_KEY")

      assert_raise ArgumentError, ~r/missing API key/, fn -> TypeSafe.new() end
      assert_raise ArgumentError, ~r/missing API key/, fn -> TypeSafe.new(api_key: "") end
    end

    test "refuses a max_retry_delay that would not cap anything" do
      for bad <- [nil, "30000", -1] do
        assert_raise ArgumentError, ~r/max_retry_delay must be a non-negative integer/, fn ->
          TypeSafe.new(api_key: "k", max_retry_delay: bad)
        end
      end
    end

    test "refuses retry_delay without a retry of its own" do
      assert_raise ArgumentError, ~r/retry_delay needs its own :retry/, fn ->
        TypeSafe.new(api_key: "k", req_options: [retry_delay: fn _ -> 0 end])
      end
    end

    test "hides the http client from inspect" do
      refute inspect(TypeSafe.new(api_key: "k")) =~ "http_client"
    end

    test "rejects unknown options" do
      assert_raise ArgumentError, ~r/unknown keys \[:modle\]/, fn ->
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
      assert {:ok, verdict} = judge().(@request)
      refute Map.has_key?(verdict, :model)
    end

    test "usage is nil when the reply omits it or reports a count the shell would refuse" do
      Req.Test.stub(__MODULE__, &Req.Test.json(&1, %{"answers" => %{}}))
      assert {:ok, %{usage: nil}} = judge().(@request)

      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{
          "answers" => %{},
          "usage" => %{"input_tokens" => -1, "output_tokens" => 0}
        })
      end)

      assert {:ok, %{usage: nil}} = judge().(@request)
    end

    test "maps the token cap to :request_too_large on 400 and 422, keeps other names" do
      for status <- [400, 422] do
        Req.Test.stub(__MODULE__, fn conn ->
          conn
          |> Plug.Conn.put_status(status)
          |> Req.Test.json(%{"detail" => %{"error_type" => "max_tokens_exceeded"}})
        end)

        assert judge().(@request) == {:error, :request_too_large}
      end

      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{"detail" => %{"error_type" => "invalid_question"}})
      end)

      assert judge().(@request) == {:error, {:bad_request, "invalid_question"}}
    end

    test "a 400 without TypeSafe's detail carries the body preview" do
      Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, 400, "nope"))
      assert judge().(@request) == {:error, {:bad_request, "nope"}}
    end

    test "a 200 without a map of answers is a malformed reply, not a verdict" do
      Req.Test.stub(__MODULE__, &Req.Test.json(&1, %{"ok" => true}))
      assert {:error, {:malformed_reply, _}} = judge().(@request)

      Req.Test.stub(__MODULE__, &Req.Test.json(&1, %{"answers" => []}))
      assert {:error, {:malformed_reply, _}} = judge().(@request)
    end

    test "maps 401, 429 with retry-after, and 5xx" do
      Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, 401, ""))
      assert judge().(@request) == {:error, :unauthorized}

      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("retry-after", "7")
        |> Plug.Conn.send_resp(429, "")
      end)

      assert judge().(@request) == {:error, {:rate_limited, 7000}}

      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("retry-after", "soon")
        |> Plug.Conn.send_resp(429, "")
      end)

      assert judge().(@request) == {:error, {:rate_limited, nil}}

      Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, 503, "down"))
      assert judge().(@request) == {:error, :server_error}
    end

    test "retries 529 and 429 with Retry-After, then succeeds" do
      for status <- [529, 429] do
        {:ok, calls} = Agent.start_link(fn -> 0 end)

        Req.Test.stub(__MODULE__, fn conn ->
          if Agent.get_and_update(calls, &{&1, &1 + 1}) == 0 do
            conn
            |> Plug.Conn.put_resp_header("retry-after", "0")
            |> Plug.Conn.send_resp(status, "later")
          else
            Req.Test.json(conn, %{"answers" => %{}})
          end
        end)

        assert {:ok, _} = retrying_judge().(@request)
        assert Agent.get(calls, & &1) == 2
      end
    end

    test "gives up after the retries and reports the last 429" do
      {:ok, calls} = Agent.start_link(fn -> 0 end)

      Req.Test.stub(__MODULE__, fn conn ->
        Agent.update(calls, &(&1 + 1))

        conn
        |> Plug.Conn.put_resp_header("retry-after", "0")
        |> Plug.Conn.send_resp(429, "")
      end)

      assert retrying_judge().(@request) == {:error, {:rate_limited, 0}}
      assert Agent.get(calls, & &1) == 4
    end

    test "an unparseable Retry-After falls back to backoff instead of raising mid-retry" do
      {:ok, calls} = Agent.start_link(fn -> 0 end)

      Req.Test.stub(__MODULE__, fn conn ->
        if Agent.get_and_update(calls, &{&1, &1 + 1}) == 0 do
          conn
          |> Plug.Conn.put_resp_header("retry-after", "soon")
          |> Plug.Conn.send_resp(429, "")
        else
          Req.Test.json(conn, %{"answers" => %{}})
        end
      end)

      assert {:ok, _} = retrying_judge(max_retry_delay: 0).(@request)
      assert Agent.get(calls, & &1) == 2
    end

    test "does not retry a timeout" do
      {:ok, calls} = Agent.start_link(fn -> 0 end)

      Req.Test.stub(__MODULE__, fn conn ->
        Agent.update(calls, &(&1 + 1))
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, {:request_error, %Req.TransportError{reason: :timeout}}} =
               retrying_judge().(@request)

      assert Agent.get(calls, & &1) == 1
    end

    test "bounds an unexpected error body" do
      Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, 418, String.duplicate("x", 5_000)))
      assert {:error, {:api_error, 418, preview}} = judge().(@request)
      assert String.length(preview) == 2_000
    end

    test "wraps transport failures" do
      Req.Test.stub(__MODULE__, &Req.Test.transport_error(&1, :econnrefused))

      assert {:error, {:request_error, %Req.TransportError{reason: :econnrefused}}} =
               judge().(@request)
    end
  end
end
