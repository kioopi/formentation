defmodule Formentation.Info do
  @moduledoc """
  The stable query surface over compiled definitions. Renderers, tooling,
  tests, and applications ask questions here instead of pattern matching
  definition internals.

  Semantic queries such as `fields/1`, `node_at/2`, `required?/2`, and
  unsupported-node enumeration are transparent to presentation-only groups
  and use semantic declaration order, which can differ from layout order.
  `root/1` and `node/2` expose native semantic and presentation storage
  without making callers pattern match definition internals.

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

  alias Formentation.{Definition, Diagnostic, InstancePath, Origin, TemplatePath}
  alias Formentation.Definition.Semantic
  alias Formentation.Info.Layout

  @doc "The root semantic object of the definition tree."
  @spec root(Definition.t()) :: Semantic.Object.t()
  def root(%Definition{semantic: root}), do: root

  @doc "Every scalar field, in semantic declaration order independent of presentation layout."
  @spec fields(Definition.t()) :: [Semantic.Field.t()]
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
  @spec unsupported_nodes(Definition.t()) :: [Semantic.Unsupported.t()]
  def unsupported_nodes(%Definition{} = definition) do
    definition |> Semantic.unsupported() |> Enum.map(& &1.node)
  end

  @doc """
  The semantic or presentation node with the given ID, or `nil` when no node
  carries it.

  Semantic IDs are resolved through the definition's semantic index first.
  Presentation layout IDs are resolved only when no semantic node uses
  the same ID.
  """
  @spec node(Definition.t(), String.t()) ::
          Semantic.Object.t()
          | Semantic.Field.t()
          | Semantic.Unsupported.t()
          | Semantic.Collection.t()
          | Formentation.Definition.Presentation.Object.t()
          | Formentation.Definition.Presentation.Field.t()
          | Formentation.Definition.Presentation.Group.t()
          | Formentation.Definition.Presentation.Collection.t()
          | nil
  def node(%Definition{semantic_index: %{by_id: by_id}, presentation: presentation}, id)
      when is_binary(id) do
    case Map.fetch(by_id, id) do
      {:ok, %{node: node}} -> node
      :error -> find_presentation_node(presentation, id)
    end
  end

  @doc """
  The node at an instance path, descending transparently through
  presentation groups; `nil` when the path names nothing. Raises
  `ArgumentError` on invalid segments.
  """
  @spec node_at(Definition.t(), [InstancePath.segment()]) ::
          Semantic.Object.t()
          | Semantic.Field.t()
          | Semantic.Unsupported.t()
          | Semantic.Collection.t()
          | nil
  def node_at(%Definition{} = definition, segments) when is_list(segments) do
    %InstancePath{segments: segments} = InstancePath.new!(segments)

    case Semantic.find(definition, segments) do
      nil -> nil
      entry -> entry.node
    end
  end

  @doc """
  Classifies the semantic node at an instance path.

  Returns `nil` when the path names no semantic node. Presentation
  group identifiers are never semantic path segments and therefore return
  `nil`. Returns `:object`, `:field`, or `:unsupported` for known semantic
  nodes. Collections resolve concrete non-negative integer segments to their
  static item template. Raises when a malformed hand-built definition makes the path
  ambiguous.
  """
  @spec semantic_kind(Definition.t(), [InstancePath.segment()]) ::
          :object | :field | :unsupported | :collection | nil
  def semantic_kind(%Definition{} = definition, segments) when is_list(segments) do
    %InstancePath{segments: segments} = InstancePath.new!(segments)

    case Semantic.find_unique(definition, segments) do
      :not_found -> nil
      {:ok, %Semantic.Entry{kind: kind}} -> kind
      {:ambiguous, count} -> raise_ambiguous_template_path!(segments, count)
    end
  end

  @doc """
  Returns the static item-template node of the collection at an instance path,
  or `nil` when that path does not name a collection.
  """
  @spec item_template(Definition.t(), [InstancePath.segment()]) ::
          Semantic.Object.t()
          | Semantic.Field.t()
          | Semantic.Unsupported.t()
          | Semantic.Collection.t()
          | nil
  def item_template(%Definition{} = definition, segments) when is_list(segments) do
    case node_at(definition, segments) do
      %Semantic.Collection{item: item} -> item
      _ -> nil
    end
  end

  @doc """
  Returns compiled field or collection constraints at an instance path.

  Nodes without constraints and missing paths return `%{}`.
  """
  @spec constraints(Definition.t(), [InstancePath.segment()]) :: map()
  def constraints(%Definition{} = definition, segments) when is_list(segments) do
    case node_at(definition, segments) do
      %Semantic.Field{constraints: constraints} -> constraints
      %Semantic.Collection{constraints: constraints} -> constraints
      _ -> %{}
    end
  end

  @doc false
  @spec semantic_node_index(Definition.t()) :: %{
          TemplatePath.t() =>
            Semantic.Object.t()
            | Semantic.Field.t()
            | Semantic.Unsupported.t()
            | Semantic.Collection.t()
        }
  def semantic_node_index(%Definition{} = definition) do
    definition
    |> Semantic.root()
    |> semantic_entries()
    |> Enum.group_by(& &1.template_path)
    |> Map.new(fn
      {path, [entry]} ->
        {path, entry.node}

      {path, matches} ->
        raise_ambiguous_template_path!(path.segments, length(matches))
    end)
  end

  defp semantic_entries(%Semantic.Entry{} = entry) do
    [entry | Enum.flat_map(Semantic.direct_children(entry), &semantic_entries/1)]
  end

  defp raise_ambiguous_template_path!(segments, count) do
    raise ArgumentError,
          "ambiguous semantic path #{inspect(segments)}: found #{count} nodes"
  end

  @doc """
  The deterministic presentation layout for the definition root.

  Presentation traversal is layout ordered and may differ from semantic
  declaration order. Field and object descriptors reference semantic
  nodes by `Formentation.TemplatePath`; presentation groups carry
  layout identity only.
  """
  @spec presentation_root(Definition.t()) :: Layout.Object.t()
  def presentation_root(%Definition{} = definition), do: Layout.root(definition)

  @doc """
  Looks up the presentation descriptor for a semantic instance path.

  Returns `:not_found` when no semantic node exists and
  `:unsupported` when the path names a preserve-only node that has no
  renderable presentation descriptor.
  """
  @spec presentation_at(Definition.t(), [InstancePath.segment()]) ::
          Layout.lookup_result()
  def presentation_at(%Definition{} = definition, segments) do
    Layout.at(definition, segments)
  end

  @doc "The compile-time diagnostics recorded on the definition."
  @spec diagnostics(Definition.t()) :: [Diagnostic.t()]
  def diagnostics(%Definition{diagnostics: diagnostics}), do: diagnostics

  @doc """
  The merged semantic and presentation provenance for the node at
  `path` — `[]` when the path names nothing.

  Semantic facts and presentation facts intentionally live on separate stored
  nodes. This query returns one list for callers that care about the public
  fact surface rather than the storage boundary; presentation-origin keys
  override semantic-origin keys if the same key appears on both sides.
  """
  @spec origins(Definition.t(), [InstancePath.segment()]) :: [{atom(), Origin.t()}]
  def origins(definition, path) do
    case node_at(definition, path) do
      nil -> []
      node -> Keyword.merge(node.origins, presentation_origins(definition, path))
    end
  end

  defp presentation_origins(%Definition{presentation: nil}, _path), do: []

  defp presentation_origins(definition, path) do
    case Layout.at(definition, path) do
      {:ok, descriptor} -> descriptor.origins
      :unsupported -> []
      :not_found -> []
    end
  end

  @doc """
  The semantic role of the field at `path`; `nil` for groups,
  unsupported nodes, and missing paths.
  """
  @spec role(Definition.t(), [InstancePath.segment()]) :: atom() | nil
  def role(definition, path) do
    case node_at(definition, path) do
      %Semantic.Field{role: role} -> role
      _group_unsupported_or_missing -> nil
    end
  end

  @doc "Whether the node at `path` is required; `false` for missing paths."
  @spec required?(Definition.t(), [InstancePath.segment()]) :: boolean()
  def required?(definition, path) do
    match?(%{required?: true}, node_at(definition, path))
  end

  defp find_presentation_node(nil, _id), do: nil

  defp find_presentation_node(%{id: id} = node, id), do: node

  # A collection stores its nested descriptor in `item`, not `children`.
  defp find_presentation_node(%Formentation.Definition.Presentation.Collection{item: item}, id) do
    find_presentation_node(item, id)
  end

  defp find_presentation_node(%{children: children}, id) do
    Enum.find_value(children, &find_presentation_node(&1, id))
  end

  defp find_presentation_node(_leaf, _id), do: nil
end
