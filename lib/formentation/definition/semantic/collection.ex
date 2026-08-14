defmodule Formentation.Definition.Semantic.Collection do
  @moduledoc """
  Native semantic homogeneous collection node (D-053).

  A collection owns exactly one anonymous item-template child at
  `template_path ++ [:item]`. Parent-key requiredness (`required?`) and
  cardinality (`:min_items`/`:max_items` in `constraints`) are independent
  axes. The item template is an ordinary semantic node carrying its own facts
  and origins.
  """

  alias Formentation.Definition.Semantic
  alias Formentation.{NodeId, Origin, TemplatePath}

  @enforce_keys [:id, :name, :template_path, :item]
  defstruct [:id, :name, :template_path, :item, required?: false, constraints: %{}, origins: []]

  @typedoc "The single anonymous item-template node."
  @type item ::
          Semantic.Object.t()
          | Semantic.Field.t()
          | Semantic.Unsupported.t()
          | __MODULE__.t()

  @doc false
  @spec new(String.t() | nil, TemplatePath.t(), item(), keyword()) :: t()
  def new(name, %TemplatePath{} = template_path, item, opts \\ [])
      when is_binary(name) or is_nil(name) do
    %__MODULE__{
      id: Keyword.get(opts, :id, NodeId.from_path(template_path)),
      name: name,
      template_path: template_path,
      item: item,
      required?: Keyword.get(opts, :required?, false),
      constraints: Keyword.get(opts, :constraints, %{}),
      origins: Keyword.get(opts, :origins, [])
    }
  end

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t() | nil,
          template_path: TemplatePath.t(),
          item: item(),
          required?: boolean(),
          constraints: map(),
          origins: [{atom(), Origin.t()}]
        }
end
