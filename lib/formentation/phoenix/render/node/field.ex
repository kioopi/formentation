defmodule Formentation.Phoenix.Render.Node.Field do
  @moduledoc """
  A single renderable control with all component-ready facts a reference
  component needs, including resolved widget, semantic `value_type`, source
  `role`, schema `required?`, Phoenix form field, and prepared DOM identities.

  `role` and `required?` are prepared meaning facts sourced directly from
  `Formentation.Definition.Semantic.Field` (D-043) — a custom UI implementation can read them without
  consulting a `Definition` or source adapter. `required?` is the schema fact
  only, intended for presentation/accessibility (e.g. an asterisk or
  `aria-required`); it must never be used to emit or infer the native HTML
  `required` attribute. That attribute continues to come solely from
  `validations[:required]` (`Phoenix.HTML.Form.input_validations/2`),
  governed by D-010's empty-string decode policy.
  """

  alias Formentation.Phoenix.Render.Node

  @enforce_keys [:widget, :field, :label, :dom, :value_type]
  defstruct [
    :widget,
    :field,
    :label,
    :dom,
    :value_type,
    :role,
    :help,
    :options,
    validations: [],
    errors: [],
    show_errors?: false,
    read_only?: false,
    required?: false
  ]

  @type t :: %__MODULE__{
          widget: atom(),
          field: Phoenix.HTML.FormField.t(),
          label: String.t(),
          dom: Node.FieldDOM.t(),
          value_type: Formentation.Definition.Semantic.Field.value_type(),
          role: atom() | nil,
          help: String.t() | nil,
          options: [Formentation.Definition.Semantic.Field.option()] | nil,
          validations: keyword(),
          errors: [{String.t(), keyword()}],
          show_errors?: boolean(),
          read_only?: boolean(),
          required?: boolean()
        }
end
