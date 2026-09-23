defmodule Cite.Wire.Object do
  @moduledoc """
  A JSON object whose key order survives encoding.

  Elixir maps of more than 32 keys iterate in hash order, so a window of 40
  candidates encoded from a map reaches the model shuffled — and the model
  reads neighbours. Wherever order carries meaning (the scan window, a list
  of candidates in a cluster's state) Cite sends one of these instead. It
  reads like a map (`object["C000"]`). Internal.
  """

  @behaviour Access

  @type t :: %__MODULE__{pairs: [{String.t(), term()}]}

  @enforce_keys [:pairs]
  defstruct [:pairs]

  @doc "Builds one from `{key, value}` pairs, in the order given."
  @spec new([{String.t(), term()}]) :: t()
  def new(pairs) when is_list(pairs), do: %__MODULE__{pairs: pairs}

  @impl Access
  def fetch(%__MODULE__{pairs: pairs}, key) do
    case List.keyfind(pairs, key, 0) do
      {_key, value} -> {:ok, value}
      nil -> :error
    end
  end

  @impl Access
  def get_and_update(%__MODULE__{pairs: pairs} = object, key, fun) do
    {_, current} = List.keyfind(pairs, key, 0, {key, nil})

    case fun.(current) do
      {get, update} -> {get, %{object | pairs: List.keystore(pairs, key, 0, {key, update})}}
      :pop -> {current, %{object | pairs: List.keydelete(pairs, key, 0)}}
    end
  end

  @impl Access
  def pop(%__MODULE__{pairs: pairs} = object, key) do
    {_, current} = List.keyfind(pairs, key, 0, {key, nil})
    {current, %{object | pairs: List.keydelete(pairs, key, 0)}}
  end
end

defimpl Jason.Encoder, for: Cite.Wire.Object do
  def encode(%{pairs: pairs}, opts),
    do: Jason.Encoder.encode(Jason.OrderedObject.new(pairs), opts)
end
