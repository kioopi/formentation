defmodule Formentation.Info do
  @moduledoc """
  The stable query surface over compiled definitions. Renderers, tooling,
  tests, and applications ask questions here instead of pattern matching
  definition internals.

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

  alias Formentation.{Definition, Diagnostic, InstancePath, Node}

  @doc "The root group of the definition tree."
  @spec root(Definition.t()) :: Node.t()
  def root(%Definition{root: root}), do: root

  @doc "Every scalar field in the tree, in declaration order."
  @spec fields(Definition.t()) :: [Node.Field.t()]
  def fields(%Definition{root: root}) do
    root |> walk() |> Enum.filter(&field?/1)
  end

  defp field?(%Node.Field{}), do: true
  defp field?(_node), do: false

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
    find_at(root, segments)
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

  defp find_at(node, []), do: node

  defp find_at(node, [segment | rest]) do
    case node |> data_children() |> Enum.find(&(&1.name == segment)) do
      nil -> nil
      child -> find_at(child, rest)
    end
  end

  defp data_children(%Node.Group{children: children}) do
    Enum.flat_map(children, fn
      %Node.Group{nests_data?: false} = group -> data_children(group)
      child -> [child]
    end)
  end

  defp data_children(_leaf), do: []
end
