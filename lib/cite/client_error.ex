defmodule Cite.ClientError do
  @moduledoc """
  A client returned something outside its contract: a bug in the client, or
  in the `Cite.Provider` behind it, not in the arguments to `Cite.judge/4`.
  `Cite` documents the contract.
  """

  defexception [:message]
end
