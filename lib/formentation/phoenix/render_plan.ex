defmodule Formentation.Phoenix.RenderPlan do
  @moduledoc false

  alias Formentation.Diagnostic
  alias Formentation.Phoenix.RenderNode

  @enforce_keys [:root]
  defstruct [:root, summary: [], diagnostics: []]

  @type summary_entry :: %{
          id: String.t() | nil,
          label: String.t() | nil,
          message: String.t()
        }

  @type t :: %__MODULE__{
          root: RenderNode.Group.t(),
          summary: [summary_entry()],
          diagnostics: [Diagnostic.t()]
        }
end
