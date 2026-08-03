defmodule Formentation.Phoenix.RenderNode.FieldDOM do
  @moduledoc """
  Exact renderer-owned DOM identities prepared for one field occurrence.

  Components consume these values verbatim; they never derive identifiers from
  Phoenix's transport-oriented field id.
  """

  @enforce_keys [:control, :help, :errors, :options]
  defstruct [:control, :help, :errors, :options]

  @type t :: %__MODULE__{
          control: String.t(),
          help: String.t(),
          errors: String.t(),
          options: [String.t()]
        }
end
