defmodule Formentation.Phoenix.RenderNode.GroupDOM do
  @moduledoc false

  @enforce_keys [:container, :help]
  defstruct [:container, :help]

  @type t :: %__MODULE__{container: String.t(), help: String.t()}
end
