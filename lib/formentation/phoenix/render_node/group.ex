defmodule Formentation.Phoenix.RenderNode.Group do
  @moduledoc """
  A rendered grouping. Data-nesting and presentational groups project to this
  one shape; their field names retain the distinction through FormData.
  """

  alias Formentation.Phoenix.RenderNode

  @enforce_keys [:legend, :dom]
  defstruct [:legend, :help, :dom, children: []]

  @type t :: %__MODULE__{
          legend: String.t() | nil,
          help: String.t() | nil,
          dom: RenderNode.GroupDOM.t(),
          children: [RenderNode.t()]
        }
end
