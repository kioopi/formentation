defmodule Formentation.Phoenix.RenderNode.FieldDOM do
  @moduledoc """
  Exact renderer-owned DOM identities prepared for one field occurrence.

  Components consume these values verbatim rather than deriving IDs from
  Phoenix's transport-oriented field ID.
  """

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
