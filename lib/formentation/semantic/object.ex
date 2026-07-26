defmodule Formentation.Semantic.Object do
  @moduledoc """
  Native semantic object occurrence.

  Objects own semantic children in declaration order. Presentation groups never
  appear in this child list.
  """

  alias Formentation.{NodeId, Origin, TemplatePath}
  alias Formentation.Semantic

  @enforce_keys [:id, :template_path]
  defstruct [
    :id,
    :name,
    :template_path,
    required?: false,
    origins: [],
    children: []
  ]

  @doc false
  @spec new(
          String.t() | nil,
          TemplatePath.t(),
          [Semantic.Object.t() | Semantic.Field.t() | Semantic.Unsupported.t()],
          keyword()
        ) ::
          t()
  def new(name, %TemplatePath{} = template_path, children, opts \\ []) when is_list(children) do
    %__MODULE__{
      id: Keyword.get(opts, :id, NodeId.from_path(template_path)),
      name: name,
      template_path: template_path,
      required?: Keyword.get(opts, :required?, false),
      origins: Keyword.get(opts, :origins, []),
      children: children
    }
  end

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t() | nil,
          template_path: TemplatePath.t(),
          required?: boolean(),
          origins: [{atom(), Origin.t()}],
          children: [Semantic.Object.t() | Semantic.Field.t() | Semantic.Unsupported.t()]
        }
end
