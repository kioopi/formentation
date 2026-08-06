defmodule Formentation.Phoenix.RenderNode.GroupDOM do
  @moduledoc """
  Exact renderer-owned DOM identities prepared for one group occurrence.

  Reference components use the prepared help identity rather than inventing a
  parallel naming convention.
  """

  @enforce_keys [:container, :help]
  defstruct [:container, :help]

  @type t :: %__MODULE__{container: String.t(), help: String.t()}
end
