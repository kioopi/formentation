defmodule Formentation.SubmissionBlocker do
  @moduledoc """
  A concrete reason the current form cannot repair a problem in its
  candidate with the capabilities its definition represents.

  Distinct from a compile-time `Formentation.Diagnostic` and an
  authoritative runtime `Formentation.Issue`: a blocker relates one or
  more issues — or a directly observable missing required value — to a
  preserve-only `Formentation.Node.Unsupported` node. It is derived at
  runtime from the materialized candidate and source-neutral validation
  issues; it is never stored on `%Formentation.Form{}`.

  - `path` — the owning unsupported node's instance path (not necessarily
    a deeper underlying issue's path).
  - `node_id` — copied from `Formentation.Node.Unsupported.id`, so tooling
    can relate the blocker to the compiled definition without parsing paths.
  - `code` — `:unsupported_required` when a required preserve-only value is
    absent from an active parent; `:unsupported_invalid` when preserved
    data has an authoritative issue at or below its path.
  - `message` — a source-neutral capability explanation for logs or a basic UI.
  - `issues` — the authoritative issues owned by the blocker, unchanged.
    Empty only for the validation-less missing-required fallback.
  """

  alias Formentation.{InstancePath, Issue}

  @enforce_keys [:path, :node_id, :code, :message]
  defstruct [:path, :node_id, :code, :message, issues: []]

  @type code :: :unsupported_required | :unsupported_invalid

  @type t :: %__MODULE__{
          path: InstancePath.t(),
          node_id: String.t(),
          code: code(),
          message: String.t(),
          issues: [Issue.t()]
        }
end
