defmodule Formentation.Phoenix.RenderPlan do
  @moduledoc """
  The render-preparation output: a render-node tree plus the submit-gated error
  summary and preparation diagnostics. The planning-note fields with no Phase 1
  behavior (fingerprint, branches, item identities) are omitted, not stubbed.
  """

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
