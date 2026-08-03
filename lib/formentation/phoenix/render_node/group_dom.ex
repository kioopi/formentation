defmodule Formentation.Phoenix.RenderNode.GroupDOM do
  @moduledoc """
  Exact renderer-owned DOM identities prepared for one group occurrence.

  Reference components render group help with the prepared help identity, so
  themes do not invent a parallel naming convention.
  """

  @enforce_keys [:container, :help]
  defstruct [:container, :help]

  @type t :: %__MODULE__{container: String.t(), help: String.t()}
end
