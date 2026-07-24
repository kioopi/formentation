defmodule Formentation.Node.Field do
  @moduledoc """
  A scalar value that can be displayed or edited (D-005, D-015). Fields
  are the leaves of the definition tree — they have no children by
  construction. `group` is the presentation-group membership id stamped
  during compilation when a declared group claims the field.

  Optional presentation properties (`label`, `help`, `widget`,
  `options`, `default`, `examples`) are `nil` when the declaration
  provides none; every filled property carries a paired entry in
  `origins`. `hidden?` renders as a hidden input but decodes normally,
  while `read_only?` excludes the field from the replace scope entirely
  (D-016).
  """

  alias Formentation.{Node, TemplatePath}

  @enforce_keys [:id, :name, :value_type, :template_path]
  defstruct [
    :id,
    :name,
    :label,
    :help,
    :role,
    :value_type,
    :widget,
    :group,
    :options,
    :default,
    :examples,
    :template_path,
    required?: false,
    hidden?: false,
    read_only?: false,
    constraints: %{},
    origins: []
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          label: String.t() | nil,
          help: String.t() | nil,
          role: atom() | nil,
          value_type: :string | :integer | :number | :boolean,
          widget: atom() | nil,
          group: String.t() | nil,
          options: [String.t()] | nil,
          default: term() | nil,
          examples: [term()] | nil,
          template_path: TemplatePath.t(),
          required?: boolean(),
          hidden?: boolean(),
          read_only?: boolean(),
          constraints: map(),
          origins: [{atom(), Node.origin()}]
        }
end
