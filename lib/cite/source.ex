defmodule Cite.Source do
  @moduledoc """
  The document as the caller's list of passages. Built by `Cite.source/2`,
  which documents `as` and `show`. Only the meta keys `show` names reach the
  model. The rest of `meta` stays with the caller.

  Shown meta goes on the wire, so its values must be JSON: `nil`, booleans,
  atoms, numbers, UTF-8 binaries, and lists and plain maps of these, with
  atom or binary keys. A map may not hold a key as both an atom and a
  string (`:k` and `"k"`): on the wire they are one key.
  """

  alias Cite.{Options, Passage, Wire}

  @type t :: %__MODULE__{
          passages: [Passage.t()],
          as: String.t(),
          show: [atom() | String.t()]
        }

  defstruct passages: [], as: "passages", show: []

  # Ids and `as` become paths like `utterances.U014.text`; whitespace, a dot,
  # a backtick, or a bracket inside one would point the question somewhere
  # else, and invalid UTF-8 would fail to encode mid-run.
  @path_breaking [".", "`", "[", "]"]
  @path_rule "must be UTF-8 with no whitespace or #{Enum.join(@path_breaking, " ")}"

  @schema Spark.Options.new!(
            as: [
              type: {:custom, __MODULE__, :validate_as, []},
              default: "passages",
              doc: """
              The key the passages sit under in every request, such as \
              `"utterances"`. It is part of every path the model reads, so it \
              must be UTF-8 with no whitespace, `.`, backtick, `[`, or `]`. \
              Passage ids follow the same rule.\
              """
            ],
            show: [
              type: {:custom, __MODULE__, :validate_show, []},
              default: [],
              doc: """
              The meta keys the model sees beside `id` and `text`, as given in \
              `meta` (`:speaker` finds `%{speaker: _}`, not `%{"speaker" => _}`). \
              It may not name `id` or `text`, or one key as both an atom and a \
              string.\
              """
            ]
          )

  @doc false
  @spec options_docs() :: String.t()
  def options_docs, do: Spark.Options.docs(@schema)

  @doc """
  Builds a source from units, each a text or `%{text: text}` with optional
  `:id` and `:meta`. Text is kept byte for byte. A unit without an id gets
  one from its position in the list: `P000`, `P001`, and so on. Raises
  `ArgumentError` on a unit, id, text, shown meta value, or option it
  cannot use.
  """
  @spec new([String.t() | map()], keyword()) :: t()
  def new(units, opts \\ [])

  def new(units, opts) when is_list(units) do
    opts = Options.read(opts, @schema)
    as = opts[:as]
    show = opts[:show]

    passages =
      units
      |> Enum.with_index()
      |> Enum.map(&passage(&1, show))
      |> reject_duplicate_ids()

    %__MODULE__{passages: passages, as: as, show: show}
  end

  def new(units, _opts) do
    raise ArgumentError,
          "units must be a list of texts or %{text: text} maps, got: #{inspect(units)}"
  end

  @doc false
  def validate_as(as) when is_binary(as) and as != "" do
    if path_part?(as),
      do: {:ok, as},
      else: {:error, "#{@path_rule}, got: #{inspect(as)}"}
  end

  def validate_as(as), do: {:error, "expected a non-empty binary, got: #{inspect(as)}"}

  @doc false
  def validate_show(show) when is_list(show) do
    cond do
      not Enum.all?(show, &(is_atom(&1) or is_binary(&1))) ->
        {:error, "expected a list of atom or binary keys, got: #{inspect(show)}"}

      Enum.any?(show, &(Wire.key(&1) in ["id", "text"])) ->
        {:error, "must not name id or text, got: #{inspect(show)}"}

      not distinct_on_wire?(show) ->
        {:error, "must not name a key as both an atom and a string, got: #{inspect(show)}"}

      true ->
        {:ok, show}
    end
  end

  def validate_show(show),
    do: {:error, "expected a list of atom or binary keys, got: #{inspect(show)}"}

  defp passage({text, index}, show) when is_binary(text),
    do: passage({%{text: text}, index}, show)

  defp passage({%{text: text} = unit, index}, show) when is_binary(text) do
    id = id(Map.get(unit, :id, default_id(index)))

    %Passage{id: id, text: text(id, text), meta: meta(id, Map.get(unit, :meta, %{}), show)}
  end

  defp passage({unit, _index}, _show) do
    raise ArgumentError, "each unit must be a text or %{text: text}, got: #{inspect(unit)}"
  end

  defp default_id(index), do: "P" <> String.pad_leading(Integer.to_string(index), 3, "0")

  defp id(id) when is_binary(id) and id != "" do
    if not path_part?(id) do
      raise ArgumentError, "passage id #{inspect(id)} #{@path_rule}: it is part of every path"
    end

    id
  end

  defp id(id) do
    raise ArgumentError, "passage id must be a non-empty binary, got: #{inspect(id)}"
  end

  defp path_part?(part) do
    String.valid?(part) and not String.contains?(part, @path_breaking) and
      not String.match?(part, ~r/\s/u)
  end

  defp text(id, text) do
    if String.valid?(text) and String.trim(text) != "" do
      text
    else
      raise ArgumentError,
            "passage #{inspect(id)} text must be non-blank valid UTF-8, got: #{inspect(text)}"
    end
  end

  # Only shown values reach the wire; the rest may hold anything.
  defp meta(id, meta, show) when is_map(meta) and not is_struct(meta) do
    case Enum.find(Map.take(meta, show), fn {_key, value} -> not json?(value) end) do
      nil ->
        meta

      {key, value} ->
        raise ArgumentError, """
        passage #{inspect(id)} shows meta #{inspect(key)}, so its value must be JSON: \
        nil, booleans, atoms, numbers, UTF-8 binaries, and lists and plain maps of \
        these with atom or binary keys, no key given as both an atom and a string; \
        got: #{inspect(value)}\
        """
    end
  end

  defp meta(id, meta, _show) do
    raise ArgumentError, "passage #{inspect(id)} meta must be a map, got: #{inspect(meta)}"
  end

  defp json?(value) when is_atom(value) or is_number(value), do: true
  defp json?(value) when is_binary(value), do: String.valid?(value)

  defp json?(list) when is_list(list),
    do: not List.improper?(list) and Enum.all?(list, &json?/1)

  defp json?(map) when is_map(map) and not is_struct(map) do
    Enum.all?(map, fn {key, value} -> json_key?(key) and json?(value) end) and
      distinct_on_wire?(Map.keys(map))
  end

  defp json?(_value), do: false

  defp json_key?(key), do: is_atom(key) or (is_binary(key) and String.valid?(key))

  # `:k` and `"k"` would reach the model as one key, whichever value survived.
  defp distinct_on_wire?(keys),
    do: length(Enum.uniq(keys)) == length(Enum.uniq_by(keys, &Wire.key/1))

  defp reject_duplicate_ids(passages) do
    dupes = for {id, n} <- Enum.frequencies_by(passages, & &1.id), n > 1, do: id

    case Enum.sort(dupes) do
      [] -> passages
      sorted -> raise ArgumentError, "passage ids must be unique, duplicated: #{inspect(sorted)}"
    end
  end
end
