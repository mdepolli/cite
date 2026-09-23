defmodule Cite.Source do
  @moduledoc """
  The document as the caller's list of passages. Built by `Cite.source/2`.

  `as` is the word the passages sit under in every request; `show` names the
  meta keys the model sees beside `id` and `text`. The rest of `meta` stays
  with the caller.
  """

  alias Cite.Passage

  @type t :: %__MODULE__{
          passages: [Passage.t()],
          as: String.t(),
          show: [atom() | String.t()]
        }

  defstruct passages: [], as: "passages", show: []

  @doc """
  Builds a source from units, each a text or `%{text: text}` with optional
  `:id` and `:meta`. Text is kept byte for byte. Missing ids default to
  `P000`, `P001`, and so on. Raises `ArgumentError` on a unit, id, text, or
  option it cannot use.
  """
  @spec new([String.t() | map()], keyword()) :: t()
  def new(units, opts \\ []) when is_list(units) do
    opts = Keyword.validate!(opts, as: "passages", show: [])
    as = opts[:as]
    show = opts[:show]

    check_as(as)
    check_show(show)

    passages =
      units
      |> Enum.with_index()
      |> Enum.map(&passage/1)
      |> reject_duplicate_ids()

    %__MODULE__{passages: passages, as: as, show: show}
  end

  defp check_as(as) when is_binary(as) and as != "", do: :ok

  defp check_as(as) do
    raise ArgumentError, "as must be a non-empty binary, got: #{inspect(as)}"
  end

  defp check_show(show) when is_list(show) do
    unless Enum.all?(show, &(is_atom(&1) or is_binary(&1))) do
      raise ArgumentError, "show must be a list of atom or binary keys, got: #{inspect(show)}"
    end

    if Enum.any?(show, &(to_string(&1) in ["id", "text"])) do
      raise ArgumentError, "show must not name id or text, got: #{inspect(show)}"
    end
  end

  defp check_show(show) do
    raise ArgumentError, "show must be a list of atom or binary keys, got: #{inspect(show)}"
  end

  defp passage({text, index}) when is_binary(text), do: passage({%{text: text}, index})

  defp passage({%{text: text} = unit, index}) when is_binary(text) do
    id = id(Map.get(unit, :id, default_id(index)))

    %Passage{id: id, text: text(id, text), meta: meta(id, Map.get(unit, :meta, %{}))}
  end

  defp passage({unit, _index}) do
    raise ArgumentError, "each unit must be a text or %{text: text}, got: #{inspect(unit)}"
  end

  defp default_id(index), do: "P" <> String.pad_leading(Integer.to_string(index), 3, "0")

  defp id(id) when is_binary(id) and id != "", do: id

  defp id(id) do
    raise ArgumentError, "passage id must be a non-empty binary, got: #{inspect(id)}"
  end

  defp text(id, text) do
    if String.valid?(text) and String.trim(text) != "" do
      text
    else
      raise ArgumentError,
            "passage #{inspect(id)} text must be non-blank valid UTF-8, got: #{inspect(text)}"
    end
  end

  defp meta(_id, meta) when is_map(meta) and not is_struct(meta), do: meta

  defp meta(id, meta) do
    raise ArgumentError, "passage #{inspect(id)} meta must be a map, got: #{inspect(meta)}"
  end

  defp reject_duplicate_ids(passages) do
    dupes = for {id, n} <- Enum.frequencies_by(passages, & &1.id), n > 1, do: id

    case Enum.sort(dupes) do
      [] -> passages
      sorted -> raise ArgumentError, "passage ids must be unique, duplicated: #{inspect(sorted)}"
    end
  end
end
