defmodule Formentation.Definition.Semantic.Unsupported do
  @moduledoc """
  Native semantic preserve-only node.

  Unsupported nodes remain discoverable through semantic traversal but
  cannot be referenced by presentation field controls.
  """

  alias Formentation.{NodeId, Origin, TemplatePath}

  @enforce_keys [:id, :name, :template_path]
  defstruct [:id, :name, :template_path, required?: false, origins: []]

  @doc false
  @spec new(String.t(), TemplatePath.t(), keyword()) :: t()
  def new(name, %TemplatePath{} = template_path, opts \\ []) when is_binary(name) do
    %__MODULE__{
      id: Keyword.get(opts, :id, NodeId.from_path(template_path)),
      name: name,
      template_path: template_path,
      required?: Keyword.get(opts, :required?, false),
      origins: Keyword.get(opts, :origins, [])
    }
  end

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          template_path: TemplatePath.t(),
          required?: boolean(),
          origins: [{atom(), Origin.t()}]
        }
end
