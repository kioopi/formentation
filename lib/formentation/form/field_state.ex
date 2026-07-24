defmodule Formentation.Form.FieldState do
  @moduledoc """
  Per-field read model assembled on demand by `Formentation.Form.field/2`
  — never stored state. `display_value` is derived (D-009 defers stored
  display values): the raw attempted value when the transport provided
  one — including when decoding failed, so the user sees what they typed
  — otherwise the current value encoded for display.
  """

  alias Formentation.{InstancePath, Issue}

  @enforce_keys [:path, :transport, :operation, :usage, :issues, :display_value]
  defstruct [:path, :transport, :operation, :usage, :issues, :display_value]

  @typedoc "What the transport carried for this field, if anything."
  @type transport :: :not_provided | {:provided, term()}

  @typedoc """
  What the carried value decoded into; `:keep` when no transition
  supplied one.
  """
  @type operation :: :keep | :unset | {:set, term()} | {:invalid, Issue.t()}

  @typedoc "Whether the user has interacted with the field (D-014)."
  @type usage :: :used | :unused | :unknown

  @type t :: %__MODULE__{
          path: InstancePath.t(),
          transport: transport(),
          operation: operation(),
          usage: usage(),
          issues: [Issue.t()],
          display_value: String.t()
        }
end
