defmodule Formentation.Presentation.Field do
  @moduledoc """
  Presentation reference to a semantic scalar field.
  """

  alias Formentation.{Origin, Presentation}

  @enforce_keys [:id, :semantic_id]
  defstruct [:id, :semantic_id, :label, :help, :widget, hidden?: false, origins: []]

  @doc false
  @spec new(String.t(), keyword()) :: t()
  def new(semantic_id, opts \\ []) when is_binary(semantic_id) do
    %__MODULE__{
      id: Keyword.get(opts, :id, Presentation.field_id(semantic_id)),
      semantic_id: semantic_id,
      label: Keyword.get(opts, :label),
      help: Keyword.get(opts, :help),
      widget: Keyword.get(opts, :widget),
      hidden?: Keyword.get(opts, :hidden?, false),
      origins: Keyword.get(opts, :origins, [])
    }
  end

  @type t :: %__MODULE__{
          id: String.t(),
          semantic_id: String.t(),
          label: String.t() | nil,
          help: String.t() | nil,
          widget: atom() | nil,
          hidden?: boolean(),
          origins: [{atom(), Origin.t()}]
        }
end
