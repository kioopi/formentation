defmodule Formentation.Phoenix.Render.Plan do
  @moduledoc """
  The render-preparation output: a render-node tree plus the submit-gated error
  summary, the instance path the plan was rooted at, and preparation
  diagnostics. The planning-note fields with no Phase 1 behavior (fingerprint,
  branches, item identities) are omitted, not stubbed.

  `root_path` is `[]` for a form projected at the root of its definition and
  the projected object's instance path for a nested one. It is what lets a
  component tell "I am the outermost render of this form" from "I am one
  subtree inside someone else's render" without decoding the projection a
  second time.
  """

  alias __MODULE__.SummaryEntry
  alias Formentation.Diagnostic
  alias Formentation.InstancePath
  alias Formentation.Phoenix.Render.Node

  @enforce_keys [:root]
  defstruct [:root, root_path: [], summary: [], diagnostics: []]

  @type t :: %__MODULE__{
          root: Node.Group.t(),
          root_path: [InstancePath.segment()],
          summary: [SummaryEntry.t()],
          diagnostics: [Diagnostic.t()]
        }
end
