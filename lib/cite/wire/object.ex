defmodule Cite.Wire.Object do
  @moduledoc """
  A JSON object whose key order survives encoding.

  Elixir maps of more than 32 keys iterate in hash order, so a window of 40
  passages encoded from a map reaches the model shuffled, and the model
  reads neighbours. Wherever order carries meaning (a screening window, a
  concern's gathered passages) Cite sends one of these instead.

  A provider meets one as a value in a request's `"state"`. It implements
  `Access`, so it reads like a map (`object["U014"]`), and `Jason.Encoder`,
  encoding as a JSON object with its keys in order; a provider that sends
  the request as JSON needs nothing else. `pairs` holds the keys and values
  in order, for a provider that converts the request to another shape.
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
