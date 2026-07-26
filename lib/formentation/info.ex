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
  alias Formentation.Info.Presentation

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

  @doc """
  Classifies the semantic occurrence at an instance path.

  Returns `nil` when the path names no semantic occurrence. Presentation
  group identifiers are never semantic path segments and therefore return
  `nil`. Returns `:object`, `:field`, or `:unsupported` for known semantic
  occurrences. Raises when a malformed hand-built definition makes the path
  ambiguous.
  """
  @spec semantic_kind(Definition.t(), [InstancePath.segment()]) ::
          :object | :field | :unsupported | nil
  def semantic_kind(%Definition{} = definition, segments) when is_list(segments) do
    %InstancePath{segments: segments} = InstancePath.new!(segments)

    case Semantic.find_unique(definition, segments) do
      :not_found -> nil
      {:ok, %Semantic.Entry{kind: kind}} -> kind
      {:ambiguous, count} -> raise_ambiguous_semantic_path!(segments, count)
    end
  end

  @doc false
  @spec semantic_node_index(Definition.t()) :: %{InstancePath.t() => Node.t()}
  def semantic_node_index(%Definition{} = definition) do
    definition
    |> Semantic.root()
    |> semantic_entries()
    |> Enum.group_by(& &1.instance_path)
    |> Map.new(fn
      {path, [entry]} ->
        {path, entry.node}

      {path, matches} ->
        raise_ambiguous_semantic_path!(path.segments, length(matches))
    end)
  end

  defp semantic_entries(%Semantic.Entry{} = entry) do
    [entry | Enum.flat_map(Semantic.direct_children(entry), &semantic_entries/1)]
  end

  defp raise_ambiguous_semantic_path!(segments, count) do
    raise ArgumentError,
          "ambiguous semantic path #{inspect(segments)}: found #{count} occurrences"
  end

  @doc """
  The deterministic presentation layout for the definition root.

  Presentation traversal is layout ordered and may differ from semantic
  declaration order. Field and object descriptors reference semantic
  occurrences by `Formentation.InstancePath`; presentation groups carry
  layout identity only.
  """
  @spec presentation_root(Definition.t()) :: Presentation.Object.t()
  def presentation_root(%Definition{} = definition), do: Presentation.root(definition)

  @doc """
  Looks up the presentation descriptor for a semantic instance path.

  Returns `:not_found` when no semantic occurrence exists and
  `:unsupported` when the path names a preserve-only node that has no
  renderable presentation descriptor.
  """
  @spec presentation_at(Definition.t(), [InstancePath.segment()]) ::
          Presentation.lookup_result()
  def presentation_at(%Definition{} = definition, segments) do
    Presentation.at(definition, segments)
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
