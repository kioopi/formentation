defmodule Formentation.Phoenix.RenderNode.Field do
  @moduledoc """
  A single renderable control with all component-ready facts a reference
  component needs, including resolved widget, semantic `value_type`, Phoenix
  form field, and prepared DOM identities.
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
