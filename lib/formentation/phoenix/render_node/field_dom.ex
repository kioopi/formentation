defmodule Formentation.Phoenix.RenderNode.FieldDOM do
  @moduledoc false

  @enforce_keys [:control, :container, :help, :errors, :options]
  defstruct [:control, :container, :help, :errors, :options]

  @type t :: %__MODULE__{
          control: String.t(),
          container: String.t(),
          help: String.t(),
          errors: String.t(),
          options: [String.t()]
        }
end
