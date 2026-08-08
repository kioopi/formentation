defmodule Formentation.Phoenix.Render.Node do
  @moduledoc """
  Vocabulary module for the render-node union.

  Render nodes are component-ready — no schema traversal remains.
  """

  alias Formentation.Phoenix.Render.Node

  @type t :: Node.Field.t() | Node.Group.t()
end
