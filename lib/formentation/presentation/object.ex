defmodule Formentation.Presentation.Object do
  @moduledoc """
  Presentation layout boundary for the root or a nested semantic object.
  """

  alias Formentation.Origin
  alias Formentation.Presentation

  @enforce_keys [:id, :semantic_id]
  defstruct [:id, :semantic_id, :label, :help, origins: [], children: []]

  @doc false
  @spec new(String.t(), [Presentation.descriptor()], keyword()) :: t()
  def new(semantic_id, children, opts \\ []) when is_binary(semantic_id) and is_list(children) do
    %__MODULE__{
      id: Keyword.get(opts, :id, Presentation.object_id(semantic_id)),
      semantic_id: semantic_id,
      label: Keyword.get(opts, :label),
      help: Keyword.get(opts, :help),
      origins: Keyword.get(opts, :origins, []),
      children: children
    }
  end

  @type t :: %__MODULE__{
          id: String.t(),
          semantic_id: String.t(),
          label: String.t() | nil,
          help: String.t() | nil,
          origins: [{atom(), Origin.t()}],
          children: [Presentation.descriptor()]
        }
end
