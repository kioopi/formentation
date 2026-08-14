defmodule Formentation.Definition.Presentation.Collection do
  @moduledoc """
  Presentation layout descriptor for a semantic collection (D-053).

  It occupies exactly one parent layout position and owns the presentation
  descriptor of the single item template. The `item` is `nil` when that
  template is unsupported.
  """

  alias Formentation.Definition.Presentation
  alias Formentation.Origin

  @enforce_keys [:id, :semantic_id]
  defstruct [:id, :semantic_id, :label, :help, :item, origins: []]

  @doc false
  @spec new(String.t(), Presentation.descriptor() | nil, keyword()) :: t()
  def new(semantic_id, item, opts \\ []) when is_binary(semantic_id) do
    %__MODULE__{
      id: Keyword.get(opts, :id, Presentation.collection_id(semantic_id)),
      semantic_id: semantic_id,
      label: Keyword.get(opts, :label),
      help: Keyword.get(opts, :help),
      item: item,
      origins: Keyword.get(opts, :origins, [])
    }
  end

  @type t :: %__MODULE__{
          id: String.t(),
          semantic_id: String.t(),
          label: String.t() | nil,
          help: String.t() | nil,
          item: Presentation.descriptor() | nil,
          origins: [{atom(), Origin.t()}]
        }
end
