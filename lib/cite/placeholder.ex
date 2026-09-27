defmodule Cite.Placeholder do
  @moduledoc """
  `{name}` placeholders in question text, and the backticked paths they
  expand to.

  A policy's questions name what they look at by role (`{passage}`,
  `{household}`); Cite replaces each with its path. The policy's
  compile-time checks use `names/1` and `name?/1`; `Cite.Wire` uses
  `instructions/4`. Internal.
  """

  @placeholder ~r/\{(\w+)\}/
  @name ~r/\A\w+\z/

  @doc """
  Whether `name` can be a placeholder: a word of letters, digits, and `_`.
  Such a name is also safe in a path.
  """
  @spec name?(String.t()) :: boolean()
  def name?(name) when is_binary(name), do: Regex.match?(@name, name)

  @doc """
  Each placeholder name in `text`, once, in order of first use. Given a list
  (a question and its focus, where the focus may be `nil`), the names across
  all of them.
  """
  @spec names(String.t() | [String.t() | nil]) :: [String.t()]
  def names(texts) when is_list(texts) do
    texts
    |> Enum.reject(&is_nil/1)
    |> Enum.flat_map(&names/1)
    |> Enum.uniq()
  end

  def names(text) when is_binary(text) do
    @placeholder
    |> Regex.scan(text, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end

  @doc "`text` with every placeholder replaced by its backticked path."
  @spec expand(String.t(), %{String.t() => String.t()}) :: String.t()
  def expand(text, paths) when is_binary(text) and is_map(paths) do
    Regex.replace(@placeholder, text, fn _match, name -> backtick(Map.fetch!(paths, name)) end)
  end

  @doc """
  The wire `instructions` for a question and its focus (`nil` for none):
  both texts expanded, plus what to read. The placeholders of both, in order
  of first use, become `inspect` when there is one and `compare` when there
  are several; with none, it is `compare` over `fallback`.
  """
  @spec instructions(String.t(), String.t() | nil, %{String.t() => String.t()}, [String.t()]) ::
          map()
  def instructions(text, focus, paths, fallback) when is_list(fallback) do
    %{"question" => expand(text, paths)}
    |> put_focus(focus, paths)
    |> Map.merge(targets(Enum.map(names([text, focus]), &Map.fetch!(paths, &1)), fallback))
  end

  defp put_focus(instructions, nil, _paths), do: instructions

  defp put_focus(instructions, focus, paths),
    do: Map.put(instructions, "focus", expand(focus, paths))

  defp targets([path], _fallback), do: %{"inspect" => backtick(path)}
  defp targets([], fallback), do: %{"compare" => Enum.map(fallback, &backtick/1)}
  defp targets(several, _fallback), do: %{"compare" => Enum.map(several, &backtick/1)}

  defp backtick(path), do: "`" <> path <> "`"
end
