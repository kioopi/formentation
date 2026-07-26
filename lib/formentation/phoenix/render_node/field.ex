defmodule Formentation.Phoenix.RenderNode.Field do
  @moduledoc """
  A single renderable control: resolved widget, the Phoenix form field,
  and everything the theme needs — no definition access required.
  `show_errors?` already folds the source's `Formentation.Phoenix.StateView`
  visibility decision (D-027), falling back to the Phoenix-generic
  usage/action rule only when the state view answers `:default` (D-014);
  themes never inspect `_unused_` markers or `form.action` themselves.
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
