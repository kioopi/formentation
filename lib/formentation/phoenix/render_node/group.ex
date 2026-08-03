defmodule Formentation.Phoenix.RenderNode.Group do
  @moduledoc """
  A rendered grouping. Both D-006 flavors (data-nesting and
  presentational) project to this one shape — the difference lives in
  the field names inside, which come from the `FormData` machinery.
  The plan root is a Group whose legend the `fields` component ignores.
  """

  alias Formentation.Phoenix.RenderNode

  @enforce_keys [:legend, :dom]
  defstruct [:legend, :dom, children: []]

  @type t :: %__MODULE__{
          legend: String.t() | nil,
          dom: RenderNode.GroupDOM.t(),
          children: [RenderNode.t()]
        }
end
