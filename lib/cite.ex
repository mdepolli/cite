defmodule Cite do
  @moduledoc """
  Finds what a policy describes in a document and cites the caller's own
  passages behind each finding, unchanged.

  Three steps:

      defmodule MyApp.Riddles do                       # declare the policy once
        use Cite.Policy

        concern :riddle do
          detect do
            question "Does {passage} pose a riddle?"
            yes "A question asked to be puzzled over."
            no "A plain question, a statement, or a remark."
          end
        end
      end

      source = Cite.source(lines)                      # hand over the passages
      report = Cite.judge(client, source, MyApp.Riddles) # judge the source against it

  `judge/4` runs two fixed rounds: a screen of every passage for every
  detect, then one judgment per finding. A decision model answers typed
  questions about the passages; it never writes text and never sees a
  passage the caller did not list.

  ## The client

  `client/2` builds one from a `Cite.Provider` module. Any 1-arity function
  of the same shape works in its place:

      request -> {:ok, verdict} | {:error, reason}

  `request` is `%{"state" => map(), "questions" => map()}`; a value in
  `"state"` may be a `Cite.Wire.Object`, a JSON object that keeps its keys
  in order. `verdict` is `%{answers: map(), usage: usage | nil}`, plus
  `:model`, the versioned id that answered, when the provider reports it.

  `judge/4` calls the client from task processes, up to `concurrency` at
  once, so it must be safe to call concurrently. Each task starts with the
  caller's Logger metadata and process level. Nothing else from the
  caller's process dictionary carries over, OpenTelemetry context included:
  a client that needs it attaches it itself.

  Tasks don't trap exits. A crash in a process the client links to ends that
  request's task, and `judge/4` exits with the same reason, even in a caller
  that traps exits, such as a GenServer.
  """

  alias Cite.{Answer, ClientError, Gather, Judge, Report, Run, Screen, Source}

  @type usage :: Report.usage()
  @type verdict :: %{
          required(:answers) => map(),
          required(:usage) => usage() | nil,
          optional(:model) => String.t()
        }
  @type client :: (map() -> {:ok, verdict()} | {:error, term()})

  @doc """
  A client backed by `provider`, a module implementing `Cite.Provider`;
  `opts` are the provider's. Build it once, where the credentials live, and
  pass it in.

      client = Cite.client(Cite.Provider.TypeSafe, api_key: System.fetch_env!("JEV_API_KEY"))
  """
  @spec client(module(), keyword()) :: client()
  def client(provider, opts \\ [])

  def client(provider, opts) when is_atom(provider) and is_list(opts) do
    handle = provider.new(opts)
    &provider.judge(handle, &1)
  end

  def client(provider, opts) when is_atom(provider) do
    raise ArgumentError, "provider options must be a keyword list, got: #{inspect(opts)}"
  end

  def client(provider, _opts) do
    raise ArgumentError,
          "provider must be a module implementing Cite.Provider, got: #{inspect(provider)}"
  end

  @doc """
  The source: the caller's passages, each a text or `%{text: text}` with
  optional `:id` and `:meta`. See `Cite.Source`.

  ## Options

  #{Source.options_docs()}
  """
  @spec source([String.t() | map()], keyword()) :: Source.t()
  defdelegate source(units, opts \\ []), to: Source, as: :new

  @doc """
  Judges `source` against `policy_module`, a module that uses `Cite.Policy`.
  Raises `ArgumentError` before any request on an argument it cannot use: a
  client that is not a 1-arity function, a source not built by `source/2`,
  a module that is not a policy, or a bad option. Raises `Cite.ClientError`
  mid-run when the client returns something outside its contract. That
  raise comes once the requests before it have answered; requests started
  meanwhile are stopped, but the provider may already have received, and
  billed, them. Nothing is sent after it.

  ## Options

  #{Run.options_docs()}
  """
  @spec judge(client(), Source.t(), module(), keyword()) :: Report.t()
  def judge(client, source, policy_module, opts \\ []) do
    client
    |> Run.new(source, policy_module, opts)
    |> screen()
    |> Gather.findings()
    |> judge_findings()
    |> Report.new()
  end

  # Round 1: every passage, a window per request.
  defp screen(%Run{} = run) do
    outcomes =
      run.source.passages
      |> Stream.chunk_every(run.window)
      |> concurrently(run, &screen_window(run, &1))
      |> Enum.concat()

    Screen.resolve(run, outcomes)
  end

  # A window over the request cap is split in half and both halves screened,
  # one after the other in the window's own task; only a single passage that
  # still exceeds it is an error.
  defp screen_window(%Run{} = run, window) do
    case fetch_verdict(run.client, Screen.request(run, window)) do
      {:error, :request_too_large} when length(window) > 1 ->
        {left, right} = Enum.split(window, div(length(window), 2))
        screen_window(run, left) ++ screen_window(run, right)

      verdict ->
        [{window, verdict}]
    end
  end

  # Round 2: one request per gathered finding.
  defp judge_findings(%Run{gathered: gathered} = run) when is_list(gathered) do
    outcomes = concurrently(gathered, run, &judge_finding(run, &1))

    Judge.resolve(run, outcomes)
  end

  # One gathered finding, judged in one request.
  defp judge_finding(%Run{} = run, gathered),
    do: {gathered, fetch_verdict(run.client, Judge.request(run, gathered))}

  # Runs `fun` on every item, up to `concurrency` at once, and returns the
  # results in item order. A raise in a task reaches the caller, with the
  # client's own stacktrace, once the results before it are in.
  defp concurrently(items, %Run{concurrency: concurrency}, fun) do
    logger = {Logger.metadata(), Logger.get_process_level(self())}

    items
    |> Task.async_stream(&attempt(fun, &1, logger),
      max_concurrency: concurrency,
      timeout: :infinity
    )
    |> Enum.map(&outcome/1)
  end

  # A task starts with an empty process dictionary; the caller's Logger
  # state goes with it, so the client logs as the caller would.
  defp attempt(fun, item, {metadata, level}) do
    Logger.metadata(metadata)
    put_process_level(level)
    fun.(item)
  catch
    kind, reason -> {:raised, kind, reason, __STACKTRACE__}
  end

  defp put_process_level(nil), do: :ok
  defp put_process_level(level), do: Logger.put_process_level(self(), level)

  defp outcome({:ok, {:raised, kind, reason, stacktrace}}),
    do: :erlang.raise(kind, reason, stacktrace)

  defp outcome({:ok, result}), do: result

  # A task killed by a linked process's exit; the stream reports it only to a
  # caller that traps exits.
  defp outcome({:exit, reason}), do: exit(reason)

  # A reply must answer every question with a value it can have; a reply that
  # skips one or answers it out of range is not a verdict on it, so the whole
  # request becomes an error rather than a "no".
  defp fetch_verdict(client, request) do
    with {:ok, verdict} <- run_client(client, request),
         :ok <- Answer.check(request["questions"], verdict.answers) do
      {:ok, verdict}
    end
  end

  # The client is the caller's function; its return is checked here, once,
  # and trusted everywhere after.
  defp run_client(client, request) do
    case client.(request) do
      {:ok, %{answers: answers, usage: usage} = verdict} when is_map(answers) ->
        check_usage(usage)
        check_model(Map.get(verdict, :model))
        {:ok, verdict}

      {:error, _reason} = error ->
        error

      other ->
        raise ClientError, """
        client must return {:ok, %{answers: map, usage: map | nil}} or {:error, reason}, \
        got: #{inspect(other)}
        """
    end
  end

  defp check_usage(nil), do: :ok

  defp check_usage(%{input_tokens: input, output_tokens: output})
       when is_integer(input) and input >= 0 and is_integer(output) and output >= 0,
       do: :ok

  defp check_usage(other) do
    raise ClientError,
          "client usage must be nil or %{input_tokens: n, output_tokens: n}, got: #{inspect(other)}"
  end

  defp check_model(nil), do: :ok
  defp check_model(model) when is_binary(model) and model != "", do: :ok

  defp check_model(other) do
    raise ClientError,
          "client model must be a non-empty binary when given, got: #{inspect(other)}"
  end
end
