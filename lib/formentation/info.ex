defmodule Formentation.Info do
  @moduledoc """
  The stable query surface over compiled definitions. Renderers, tooling,
  tests, and applications ask questions here instead of pattern matching
  definition internals.

  Semantic queries such as `fields/1`, `node_at/2`, `required?/2`, and
  unsupported-node enumeration are transparent to presentation-only groups
  and use semantic declaration order, which can differ from layout order.
  `root/1` and `node/2` remain compatibility access to the current mixed
  tree until the definition storage split lands.

  ## Example

      iex> {:ok, definition, []} =
      ...>   Formentation.compile(
      ...>     %{kind: :object, properties: [{"name", %{kind: :string}}]},
      ...>     adapter: Formentation.Source.Map
      ...>   )
      iex> Formentation.Info.role(definition, ["name"])
      :text
      iex> Formentation.Info.required?(definition, ["name"])
      false
  """

  alias Formentation.{Definition, Diagnostic, InstancePath, Node, Semantic}

  @doc "The root group of the definition tree."
  @spec root(Definition.t()) :: Node.t()
  def root(%Definition{root: root}), do: root

  @doc "Every scalar field, in semantic declaration order independent of presentation layout."
  @spec fields(Definition.t()) :: [Node.Field.t()]
  def fields(%Definition{} = definition) do
    definition |> Semantic.fields() |> Enum.map(& &1.node)
  end

  @doc """
  Every unsupported (preserve-only) node in the tree, in declaration
  order, descending through data-nesting groups and looking through
  presentation-only groups.
  `[]` when none exist. Each node is preserve-only; `required?: true`
  flags a likely creation-form risk but does not prove any instance is
  blocked — the runtime submission-status functions on `Formentation.Form`
  decide that.

      iex> {:ok, definition, _} =
      ...>   Formentation.compile(
      ...>     %{kind: :object, properties: [{"attachment", %{kind: :file}}]},
      ...>     adapter: Formentation.Source.Map
      ...>   )
      iex> definition |> Formentation.Info.unsupported_nodes() |> Enum.map(& &1.name)
      ["attachment"]
  """
  @spec unsupported_nodes(Definition.t()) :: [Node.Unsupported.t()]
  def unsupported_nodes(%Definition{} = definition) do
    definition |> unsupported_nodes_with_paths() |> Enum.map(fn {_path, node} -> node end)
  end

  @doc false
  @spec unsupported_nodes_with_paths(Definition.t()) :: [{InstancePath.t(), Node.Unsupported.t()}]
  def unsupported_nodes_with_paths(%Definition{} = definition) do
    definition
    |> Semantic.unsupported()
    |> Enum.map(fn entry -> {entry.instance_path, entry.node} end)
  end

  @doc """
  The node with the given ID (`Formentation.NodeId` vocabulary), or
  `nil` when no node carries it.
  """
  @spec node(Definition.t(), String.t()) :: Node.t() | nil
  def node(%Definition{root: root}, id) when is_binary(id) do
    root |> walk() |> Enum.find(&(&1.id == id))
  end

  @doc """
  The node at an instance path, descending transparently through
  presentation groups; `nil` when the path names nothing. Raises
  `ArgumentError` on invalid segments.
  """
  @spec node_at(Definition.t(), [InstancePath.segment()]) :: Node.t() | nil
  def node_at(%Definition{root: root}, segments) when is_list(segments) do
    %InstancePath{segments: segments} = InstancePath.new!(segments)

    case Semantic.find(%Definition{root: root}, segments) do
      nil -> nil
      entry -> entry.node
    end
  end

  @doc "The compile-time diagnostics recorded on the definition."
  @spec diagnostics(Definition.t()) :: [Diagnostic.t()]
  def diagnostics(%Definition{diagnostics: diagnostics}), do: diagnostics

  @doc """
  The provenance list of the node at `path` — `[]` when the path names
  nothing.
  """
  @spec origins(Definition.t(), [InstancePath.segment()]) :: [{atom(), Node.origin()}]
  def origins(definition, path) do
    case node_at(definition, path) do
      nil -> []
      node -> node.origins
    end
  end

  @doc """
  The semantic role of the field at `path`; `nil` for groups,
  unsupported nodes, and missing paths.
  """
  @spec role(Definition.t(), [InstancePath.segment()]) :: atom() | nil
  def role(definition, path) do
    case node_at(definition, path) do
      %Node.Field{role: role} -> role
      _group_unsupported_or_missing -> nil
    end
  end

  @doc "Whether the node at `path` is required; `false` for missing paths."
  @spec required?(Definition.t(), [InstancePath.segment()]) :: boolean()
  def required?(definition, path) do
    match?(%{required?: true}, node_at(definition, path))
  end

  defp walk(%Node.Group{children: children} = node) do
    [node | Enum.flat_map(children, &walk/1)]
  end

  defp walk(leaf), do: [leaf]
end
