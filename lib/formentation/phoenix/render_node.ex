defmodule Formentation.Phoenix.RenderNode do
  @moduledoc """
  Vocabulary module for the render-node union, mirroring
  `Formentation.Node` (D-015): one struct per kind, split on shape.
  Render nodes are component-ready — no schema traversal remains.
  """

  alias Formentation.Phoenix.RenderNode

  @type t :: RenderNode.Field.t() | RenderNode.Group.t()
end
