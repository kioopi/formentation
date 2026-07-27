defmodule Formentation.Presentation.Group do
  @moduledoc """
  Presentation-only layout group.

  A group owns layout identity and ordered children, but no semantic path.
  """

  alias Formentation.Origin
  alias Formentation.Presentation

  @enforce_keys [:id]
  defstruct [:id, :label, :help, origins: [], children: []]

  @doc false
  @spec new(String.t(), [Presentation.descriptor()], keyword()) :: t()
  def new(id, children, opts \\ []) when is_binary(id) and is_list(children) do
    %__MODULE__{
      id: id,
      label: Keyword.get(opts, :label),
      help: Keyword.get(opts, :help),
      origins: Keyword.get(opts, :origins, []),
      children: children
    }
  end

  @type t :: %__MODULE__{
          id: String.t(),
          label: String.t() | nil,
          help: String.t() | nil,
          origins: [{atom(), Origin.t()}],
          children: [Presentation.descriptor()]
        }
end
