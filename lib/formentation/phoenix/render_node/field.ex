defmodule Formentation.Phoenix.RenderNode.Field do
  @moduledoc """
  A single renderable control: resolved widget, the Phoenix form field,
  and everything the theme needs — no definition access required.
  `show_errors?` already folds usage and action (D-014); themes never
  inspect `_unused_` markers.
  """

  @enforce_keys [:widget, :field, :label]
  defstruct [
    :widget,
    :field,
    :label,
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
          help: String.t() | nil,
          options: [String.t()] | nil,
          validations: keyword(),
          errors: [{String.t(), keyword()}],
          show_errors?: boolean(),
          read_only?: boolean()
        }
end
