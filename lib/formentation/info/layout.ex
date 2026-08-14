defmodule Formentation.Info.Layout do
  @moduledoc """
  Typed presentation traversal descriptors returned by `Formentation.Info`.

  These structs describe the current layout query contract over a compiled
  definition. They are descriptors over native presentation storage, not the
  stored presentation structs themselves.
  """

  alias Formentation.{Definition, InstancePath, Origin, TemplatePath}
  alias Formentation.Definition.Presentation, as: Layout
  alias Formentation.Definition.Semantic

  defmodule Object do
    @moduledoc """
    A root or nested semantic-object layout boundary.

    `template_path` identifies the object node. `id` is layout identity
    for the current descriptor and must not be parsed as an instance path.
    """

    @enforce_keys [:id, :template_path, :label, :help, :origins, :children]
    defstruct [:id, :template_path, :label, :help, :origins, children: []]

    @type t :: %__MODULE__{
            id: String.t(),
            template_path: TemplatePath.t(),
            label: String.t() | nil,
            help: String.t() | nil,
            origins: [{atom(), Origin.t()}],
            children: [Formentation.Info.Layout.descriptor()]
          }
  end

  defmodule Field do
    @moduledoc "A scalar field reference carrying presentation-owned facts."

    @enforce_keys [:template_path, :label, :help, :widget, :hidden?, :origins]
    defstruct [:template_path, :label, :help, :widget, :origins, hidden?: false]

    @type t :: %__MODULE__{
            template_path: TemplatePath.t(),
            label: String.t() | nil,
            help: String.t() | nil,
            widget: atom() | nil,
            hidden?: boolean(),
            origins: [{atom(), Origin.t()}]
          }
  end

  defmodule Group do
    @moduledoc """
    A presentation-only layout group.

    Groups carry layout identity and child order but never semantic instance
    paths.
    """

    @enforce_keys [:id, :label, :help, :origins, :children]
    defstruct [:id, :label, :help, :origins, children: []]

    @type t :: %__MODULE__{
            id: String.t(),
            label: String.t() | nil,
            help: String.t() | nil,
            origins: [{atom(), Origin.t()}],
            children: [Formentation.Info.Layout.descriptor()]
          }
  end

  defmodule Collection do
    @moduledoc "A collection layout boundary owning its item-template descriptor."

    @enforce_keys [:id, :template_path, :label, :help, :origins, :item]
    defstruct [:id, :template_path, :label, :help, :origins, :item]

    @type t :: %__MODULE__{
            id: String.t(),
            template_path: TemplatePath.t(),
            label: String.t() | nil,
            help: String.t() | nil,
            origins: [{atom(), Origin.t()}],
            item: Formentation.Info.Layout.descriptor() | nil
          }
  end

  @type descriptor :: Object.t() | Field.t() | Group.t() | Collection.t()
  @type lookup_result :: {:ok, descriptor()} | :not_found | :unsupported

  @spec root(Definition.t()) :: Object.t()
  def root(%Definition{presentation: %Layout.Object{} = root} = definition) do
    object(root, definition)
  end

  def root(%Definition{presentation: nil}) do
    missing_presentation_storage!()
  end

  @spec at(Definition.t(), [InstancePath.segment()]) :: lookup_result()
  def at(%Definition{} = definition, segments) when is_list(segments) do
    %InstancePath{segments: segments} = InstancePath.new!(segments)

    case unique_semantic_entry(definition, segments) do
      {:error, :not_found} -> :not_found
      {:error, :unsupported} -> :unsupported
      {:ok, %Semantic.Entry{} = entry} -> {:ok, descriptor(entry, definition)}
    end
  end

  defp descriptor(%Semantic.Entry{kind: :object} = entry, definition),
    do: definition |> layout_by_semantic_id!(entry.node.id) |> object(definition)

  defp descriptor(%Semantic.Entry{kind: :field} = entry, definition),
    do: definition |> layout_by_semantic_id!(entry.node.id) |> field(definition)

  defp descriptor(%Semantic.Entry{kind: :collection} = entry, definition),
    do: definition |> layout_by_semantic_id!(entry.node.id) |> collection(definition)

  defp object(%Layout.Object{} = object, definition) do
    entry = semantic_entry_by_id!(definition, object.semantic_id, :object)

    %Object{
      template_path: entry.template_path,
      id: object.id,
      label: object.label,
      help: object.help,
      origins: object.origins,
      children: object_children(object.children, definition)
    }
  end

  defp object_children(nodes, %Definition{} = definition) do
    nodes
    |> Enum.map(&layout_descriptor(&1, definition))
    |> Enum.reject(&is_nil/1)
  end

  defp layout_descriptor(%Layout.Object{} = object, definition), do: object(object, definition)

  defp layout_descriptor(%Layout.Group{} = group, definition) do
    %Group{
      id: group.id,
      label: group.label,
      help: group.help,
      origins: group.origins,
      children: object_children(group.children, definition)
    }
  end

  defp layout_descriptor(%Layout.Field{} = field, definition), do: field(field, definition)

  defp layout_descriptor(%Layout.Collection{} = collection, definition),
    do: collection(collection, definition)

  defp collection(%Layout.Collection{} = collection, definition) do
    entry = semantic_entry_by_id!(definition, collection.semantic_id, :collection)

    %Collection{
      id: collection.id,
      template_path: entry.template_path,
      label: collection.label,
      help: collection.help,
      origins: collection.origins,
      item: collection.item && layout_descriptor(collection.item, definition)
    }
  end

  defp field(%Layout.Field{} = field, definition) do
    entry = semantic_entry_by_id!(definition, field.semantic_id, :field)

    %Field{
      template_path: entry.template_path,
      label: field.label,
      help: field.help,
      widget: field.widget,
      hidden?: field.hidden?,
      origins: field.origins
    }
  end

  defp semantic_entry_by_id!(
         %Definition{semantic_index: %{by_id: by_id}},
         semantic_id,
         expected_kind
       ) do
    case Map.fetch(by_id, semantic_id) do
      {:ok, %{kind: ^expected_kind, node: node}} ->
        semantic_entry(expected_kind, node)

      {:ok, %{kind: found_kind, node: node}} ->
        wrong_kind_reference!(node.template_path.segments, expected_kind, found_kind)

      :error ->
        raise ArgumentError,
              "invalid presentation reference #{inspect(semantic_id)}: expected a " <>
                "#{expected_kind} node, found none"
    end
  end

  defp semantic_entry(kind, %{name: name, template_path: template_path} = node) do
    %Semantic.Entry{
      kind: kind,
      name: name,
      node: node,
      template_path: template_path
    }
  end

  defp layout_by_semantic_id!(%Definition{presentation: %Layout.Object{} = root}, semantic_id) do
    find_layout_by_semantic_id(root, semantic_id) ||
      raise ArgumentError,
            "invalid presentation reference #{inspect(semantic_id)}: expected exactly one " <>
              "presentation descriptor, found none"
  end

  defp layout_by_semantic_id!(%Definition{presentation: nil}, _semantic_id) do
    missing_presentation_storage!()
  end

  defp missing_presentation_storage! do
    raise ArgumentError, "invalid presentation query: definition has no presentation storage"
  end

  defp find_layout_by_semantic_id(%Layout.Object{semantic_id: semantic_id} = object, semantic_id),
    do: object

  defp find_layout_by_semantic_id(%Layout.Object{children: children}, semantic_id) do
    find_layout_child_by_semantic_id(children, semantic_id)
  end

  defp find_layout_by_semantic_id(%Layout.Group{children: children}, semantic_id) do
    find_layout_child_by_semantic_id(children, semantic_id)
  end

  defp find_layout_by_semantic_id(%Layout.Field{semantic_id: semantic_id} = field, semantic_id),
    do: field

  defp find_layout_by_semantic_id(%Layout.Field{}, _semantic_id), do: nil

  defp find_layout_by_semantic_id(
         %Layout.Collection{semantic_id: semantic_id} = collection,
         semantic_id
       ),
       do: collection

  defp find_layout_by_semantic_id(%Layout.Collection{item: nil}, _semantic_id), do: nil

  defp find_layout_by_semantic_id(%Layout.Collection{item: item}, semantic_id),
    do: find_layout_by_semantic_id(item, semantic_id)

  defp find_layout_child_by_semantic_id(children, semantic_id) do
    Enum.find_value(children, &find_layout_by_semantic_id(&1, semantic_id))
  end

  defp unique_semantic_entry(definition, segments) do
    case Semantic.find_unique(definition, segments) do
      :not_found -> {:error, :not_found}
      {:ok, %Semantic.Entry{kind: :unsupported}} -> {:error, :unsupported}
      {:ok, %Semantic.Entry{} = entry} -> {:ok, entry}
      {:ambiguous, count} -> ambiguous_reference!(segments, count)
    end
  end

  defp ambiguous_reference!(segments, count) do
    raise ArgumentError,
          "invalid presentation reference #{inspect(segments)}: expected exactly " <>
            "one semantic node, found #{count}"
  end

  defp wrong_kind_reference!(segments, expected_kind, found_kind) do
    raise ArgumentError,
          "invalid presentation reference #{inspect(segments)}: expected a " <>
            "#{expected_kind} node, found #{found_kind}"
  end
end
