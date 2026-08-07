defmodule Formentation.Phoenix.RenderNode.Group do
  @moduledoc """
  A rendered grouping. Data-nesting and presentational groups project to this
  one shape; their field names retain the distinction through FormData, and
  now also through `kind` and `occurrence_path` — added so summary linking
  (#34) can tell them apart without inferring provenance from DOM-id text,
  legend content, or child shape. `kind` is `:object` for a semantic object's
  occurrence and `:presentation_group` for a presentation-only grouping;
  callers never derive it any other way. Only `:object` groups carry a
  non-nil `occurrence_path` — the exact `InstancePath` of that occurrence.
  """

  alias Formentation.InstancePath
  alias Formentation.Phoenix.RenderNode

  @enforce_keys [:legend, :dom, :kind]
  defstruct [:legend, :help, :dom, :occurrence_path, :kind, children: []]

  @type t :: %__MODULE__{
          legend: String.t() | nil,
          help: String.t() | nil,
          dom: RenderNode.GroupDOM.t(),
          kind: :object | :presentation_group,
          occurrence_path: InstancePath.t() | nil,
          children: [RenderNode.t()]
        }
end
