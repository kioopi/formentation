defmodule Formentation.Node.Unsupported do
  @moduledoc """
  A declared construct the compiler preserves without interpreting
  (D-015). It keeps its place in the tree, its value survives
  materialization untouched (D-009), and it never decodes, validates,
  or renders.

  This is a **preserve-only capability**, not a verdict on any concrete
  instance: the paired warning `Formentation.Diagnostic` records why the
  compiler could not interpret the construct, but it describes what the
  *definition* can never do — decode, replace, or render this construct
  — not whether any particular instance is currently in trouble. A form
  can carry an unsupported node and stay submittable indefinitely, as
  long as the preserved value stays present (when required) and valid.

  Concrete submission impact is a runtime question, derived — never
  stored — from the materialized candidate and the source-neutral
  validation issues attached to it: see `Formentation.Form.submission_status/1`
  and `Formentation.Form.submission_blockers/1`. Every unsupported node
  in a definition, whether or not any instance currently blocks on it,
  is enumerated statically by `Formentation.Info.unsupported_nodes/1`.
  """

  alias Formentation.{Node, TemplatePath}

  @enforce_keys [:id, :name, :template_path]
  defstruct [:id, :name, :template_path, required?: false, origins: []]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          template_path: TemplatePath.t(),
          required?: boolean(),
          origins: [{atom(), Node.origin()}]
        }
end
