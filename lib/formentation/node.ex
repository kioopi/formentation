defmodule Formentation.Node do
  @moduledoc """
  The node vocabulary of a compiled definition (D-015).

  Each node kind is its own struct — `Formentation.Node.Field`,
  `Formentation.Node.Group`, and `Formentation.Node.Unsupported` — so a
  node's shape documents its invariants: only groups carry `children`,
  only fields carry `value_type`. Kinds split when their shape differs,
  not when their values differ: scalar fields stay one struct, while
  future kinds with new shapes (collections, choices) get new structs.

  This module holds what the kinds share: the `t/0` union and the
  `origin/0` provenance tag type (D-003).
  """

  alias Formentation.Node.{Field, Group, Unsupported}

  @typedoc """
  One provenance tag (D-003): which source vocabulary contributed a node
  property, and where in that source. A node's `origins` list pairs the
  property it explains with one of these.
  """
  @type origin ::
          {:map_source, [atom() | String.t()]}
          | {:json_schema, String.t()}
          | {:ui_hints, String.t()}
          | {:inference, atom()}

  @typedoc "Any compiled node."
  @type t :: Field.t() | Group.t() | Unsupported.t()
end
