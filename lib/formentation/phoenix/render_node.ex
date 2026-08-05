defmodule Formentation.Phoenix.RenderNode do
  @moduledoc """
  Vocabulary module for the render-node union.

  Render nodes are component-ready — no schema traversal remains.
  """

  alias Formentation.Phoenix.RenderNode

  @type t :: RenderNode.Field.t() | RenderNode.Group.t()
end
