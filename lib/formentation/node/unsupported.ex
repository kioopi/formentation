defmodule Formentation.Node.Unsupported do
  @moduledoc """
  A declared construct the compiler preserves without interpreting
  (D-015). It keeps its place in the tree, its value survives
  materialization untouched (D-009), and it never decodes or validates.
  The paired warning diagnostic carries the reason it is unsupported.
  """

  alias Formentation.{Node, TemplatePath}

  @enforce_keys [:id, :name, :template_path]
  defstruct [:id, :name, :template_path, required?: false, origins: []]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          template_path: TemplatePath.t(),
          required?: boolean(),
          origins: [{atom(), Node.origin()}]
        }
end
