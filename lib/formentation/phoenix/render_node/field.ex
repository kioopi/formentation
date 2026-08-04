defmodule Formentation.Phoenix.RenderNode.Field do
  @moduledoc """
  A single renderable control with all component-ready facts a theme needs —
  no definition access required. Those facts include the resolved `widget`,
  normalized semantic `value_type`, Phoenix form field, and prepared `dom`
  identities. Widget and value type are orthogonal: integer and general-number
  fields can share `:number_input`, while an explicit widget changes
  presentation without changing semantic type.
  `show_errors?` already folds the source's `Formentation.Phoenix.StateView`
  visibility decision (D-027), falling back to the Phoenix-generic
  usage/action rule only when the state view answers `:default` (D-014);
  themes never inspect `_unused_` markers or `form.action` themselves.
  """

  alias Formentation.Phoenix.RenderNode

  @enforce_keys [:widget, :field, :label, :dom, :value_type]
  defstruct [
    :widget,
    :field,
    :label,
    :dom,
    :value_type,
    :help,
    :options,
    validations: [],
    errors: [],
    show_errors?: false,
    read_only?: false
  ]

  @type t :: %__MODULE__{
          widget: atom(),
          field: Phoenix.HTML.FormField.t(),
          label: String.t(),
          dom: RenderNode.FieldDOM.t(),
          value_type: Formentation.Semantic.Field.value_type(),
          help: String.t() | nil,
          options: [Formentation.Semantic.Field.option()] | nil,
          validations: keyword(),
          errors: [{String.t(), keyword()}],
          show_errors?: boolean(),
          read_only?: boolean()
        }
end
