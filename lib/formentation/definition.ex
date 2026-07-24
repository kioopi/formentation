defmodule Formentation.Definition do
  @moduledoc """
  The static, source-independent representation of a form's meaning.

  Safe to cache and inspect; never contains runtime params, field errors,
  or DOM identifiers. `format_version` names the layout of this struct so
  cached definitions can be invalidated across releases. `validator` is
  an opaque instance-validation artifact owned by the source adapter's
  validator module; `nil` when the source provides none.
  """

  alias Formentation.{Diagnostic, Node}

  @format_version 1

  @enforce_keys [:root]
  defstruct [:root, :validator, format_version: @format_version, diagnostics: []]

  @type t :: %__MODULE__{
          format_version: pos_integer(),
          root: Node.t(),
          diagnostics: [Diagnostic.t()],
          validator: term() | nil
        }
end
