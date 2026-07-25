defmodule Formentation.Definition do
  @moduledoc """
  The static, source-independent representation of a form's meaning.

  Safe to cache and inspect; never contains runtime params, field errors,
  or DOM identifiers. `format_version` names the layout of this struct so
  cached definitions can be invalidated across releases. `validation` is
  an optional `Formentation.ValidationPlan` — an executable module paired
  with the opaque artifact that module owns and interprets; `nil` when the
  source supplies no authoritative instance validation (the map source,
  currently).
  """

  alias Formentation.{Diagnostic, Node, ValidationPlan}

  @format_version 2

  @enforce_keys [:root]
  defstruct [:root, :validation, format_version: @format_version, diagnostics: []]

  @type t :: %__MODULE__{
          format_version: pos_integer(),
          root: Node.t(),
          diagnostics: [Diagnostic.t()],
          validation: ValidationPlan.t() | nil
        }
end
