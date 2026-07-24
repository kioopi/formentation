defmodule Formentation.Diagnostic do
  @moduledoc """
  A problem with declaration processing: invalid declarations, unsupported
  constructs, exhausted budgets. Distinct from a runtime `Issue`, which
  concerns a submitted instance and arrives with the form-state slice.

  `origin` and `template_path` are `nil` when the problem cannot be
  attributed to a declaration location.
  """

  alias Formentation.{Node, TemplatePath}

  @enforce_keys [:severity, :code, :message]
  defstruct [:severity, :code, :message, :origin, :template_path]

  @type t :: %__MODULE__{
          severity: :error | :warning,
          code: atom(),
          message: String.t(),
          origin: Node.origin() | nil,
          template_path: TemplatePath.t() | nil
        }
end
