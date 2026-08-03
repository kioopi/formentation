defmodule Formentation.Phoenix.RenderNode.GroupDOM do
  @moduledoc """
  Exact renderer-owned DOM identities prepared for one group occurrence.

  Group help content is not rendered yet, but its identity is prepared so a
  future component cannot invent a parallel naming convention.
  """

  @enforce_keys [:container, :help]
  defstruct [:container, :help]

  @type t :: %__MODULE__{container: String.t(), help: String.t()}
end
