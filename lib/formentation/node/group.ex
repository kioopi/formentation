defmodule Formentation.Node.Group do
  @moduledoc """
  An object-like container or a purely presentational grouping,
  distinguished by `nests_data?` (D-006, D-015). A data-nesting group
  contributes an instance-path segment; a presentational group is
  transparent to instance paths. `nests_data?` is enforced so every
  construction site declares which flavor it builds.
  """

  alias Formentation.{Node, TemplatePath}

  @enforce_keys [:id, :template_path, :nests_data?]
  defstruct [
    :id,
    :name,
    :label,
    :help,
    :template_path,
    :declaration_order,
    :nests_data?,
    required?: false,
    origins: [],
    children: []
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t() | nil,
          label: String.t() | nil,
          help: String.t() | nil,
          template_path: TemplatePath.t(),
          declaration_order: non_neg_integer() | nil,
          nests_data?: boolean(),
          required?: boolean(),
          origins: [{atom(), Node.origin()}],
          children: [Node.t()]
        }
end
