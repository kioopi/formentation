defmodule Formentation.Info.Presentation do
  @moduledoc """
  Typed presentation traversal descriptors returned by `Formentation.Info`.

  These structs describe the current layout query contract over a compiled
  definition. They are descriptors, not stored definition state: the current
  implementation derives them from the compatibility mixed tree on demand.
  """

  alias Formentation.{Definition, InstancePath, Node, Semantic}
  alias Formentation.Presentation, as: Layout

  defmodule Object do
    @moduledoc """
    A root or nested semantic-object layout boundary.

    `semantic_path` identifies the object occurrence. `id` is layout identity
    for the current descriptor and must not be parsed as an instance path.
    """

    @enforce_keys [:id, :semantic_path, :label, :help, :origins, :children]
    defstruct [:id, :semantic_path, :label, :help, :origins, children: []]

    @type t :: %__MODULE__{
            id: String.t(),
            semantic_path: InstancePath.t(),
            label: String.t() | nil,
            help: String.t() | nil,
            origins: [{atom(), Node.origin()}],
            children: [Formentation.Info.Presentation.descriptor()]
          }
  end

  defmodule Field do
    @moduledoc "A scalar field reference carrying presentation-owned facts."

    @enforce_keys [:semantic_path, :label, :help, :widget, :hidden?, :origins]
    defstruct [:semantic_path, :label, :help, :widget, :origins, hidden?: false]

    @type t :: %__MODULE__{
            semantic_path: InstancePath.t(),
            label: String.t() | nil,
            help: String.t() | nil,
            widget: atom() | nil,
            hidden?: boolean(),
            origins: [{atom(), Node.origin()}]
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
            origins: [{atom(), Node.origin()}],
            children: [Formentation.Info.Presentation.descriptor()]
          }
  end

  @type descriptor :: Object.t() | Field.t() | Group.t()
  @type lookup_result :: {:ok, descriptor()} | :not_found | :unsupported

  @spec root(Definition.t()) :: Object.t()
  def root(%Definition{presentation: %Layout.Object{} = root} = definition) do
    object(root, definition)
  end

  def root(%Definition{} = definition) do
    definition
    |> Semantic.root()
    |> object(definition)
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

  defp descriptor(
         %Semantic.Entry{kind: :object} = entry,
         %Definition{presentation: nil} = definition
       ),
       do: object(entry, definition)

  defp descriptor(%Semantic.Entry{kind: :object} = entry, definition),
    do: definition |> layout_by_semantic_id!(entry.node.id) |> object(definition)

  defp descriptor(%Semantic.Entry{kind: :field} = entry, %Definition{presentation: nil}),
    do: field(entry)

  defp descriptor(%Semantic.Entry{kind: :field} = entry, definition),
    do: definition |> layout_by_semantic_id!(entry.node.id) |> field(definition)

  defp object(%Layout.Object{} = object, definition) do
    entry = semantic_entry_by_id!(definition, object.semantic_id, :object)

    %Object{
      semantic_path: entry.instance_path,
      id: object.id,
      label: object.label,
      help: object.help,
      origins: object.origins,
      children: object_children(object.children, definition)
    }
  end

  defp object(
         %Semantic.Entry{kind: :object, node: node, instance_path: path} = entry,
         _definition
       ) do
    %Object{
      semantic_path: path,
      id: node.id,
      label: node.label,
      help: node.help,
      origins: node.origins,
      children: object_children(node.children, semantic_index(entry))
    }
  end

  defp object_children(nodes, %Definition{} = definition) do
    nodes
    |> Enum.map(&layout_descriptor(&1, definition))
    |> Enum.reject(&is_nil/1)
  end

  defp object_children(nodes, semantic_index) do
    nodes
    |> Enum.map(&layout_descriptor(&1, semantic_index))
    |> Enum.reject(&is_nil/1)
  end

  defp layout_descriptor(%Node.Group{nests_data?: true} = node, semantic_index) do
    entry = unique_child!(semantic_index, node.name, :object)

    %Object{
      id: node.id,
      semantic_path: entry.instance_path,
      label: node.label,
      help: node.help,
      origins: node.origins,
      children: object_children(node.children, semantic_index(entry))
    }
  end

  defp layout_descriptor(%Node.Group{nests_data?: false} = node, semantic_index) do
    %Group{
      id: node.id,
      label: node.label,
      help: node.help,
      origins: node.origins,
      children: object_children(node.children, semantic_index)
    }
  end

  defp layout_descriptor(%Node.Field{} = node, semantic_index) do
    entry = unique_child!(semantic_index, node.name, :field)

    %Field{
      semantic_path: entry.instance_path,
      label: node.label,
      help: node.help,
      widget: node.widget,
      hidden?: node.hidden?,
      origins: node.origins
    }
  end

  defp layout_descriptor(%Node.Unsupported{}, _semantic_index), do: nil

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

  defp field(%Semantic.Entry{kind: :field, node: node, instance_path: path}) do
    %Field{
      semantic_path: path,
      label: node.label,
      help: node.help,
      widget: node.widget,
      hidden?: node.hidden?,
      origins: node.origins
    }
  end

  defp field(%Layout.Field{} = field, definition) do
    entry = semantic_entry_by_id!(definition, field.semantic_id, :field)

    %Field{
      semantic_path: entry.instance_path,
      label: field.label,
      help: field.help,
      widget: field.widget,
      hidden?: field.hidden?,
      origins: field.origins
    }
  end

  defp semantic_entry_by_id!(
         %Definition{semantic_index: %{by_id: by_id}} = definition,
         semantic_id,
         expected_kind
       ) do
    case Map.fetch(by_id, semantic_id) do
      {:ok, %{kind: ^expected_kind, node: node}} ->
        Semantic.find(definition, node.template_path.segments)

      {:ok, %{kind: found_kind, node: node}} ->
        wrong_kind_reference!(node.template_path.segments, expected_kind, found_kind)

      :error ->
        raise ArgumentError,
              "invalid presentation reference #{inspect(semantic_id)}: expected a " <>
                "#{expected_kind} occurrence, found none"
    end
  end

  defp layout_by_semantic_id!(%Definition{presentation: %Layout.Object{} = root}, semantic_id) do
    find_layout_by_semantic_id(root, semantic_id) ||
      raise ArgumentError,
            "invalid presentation reference #{inspect(semantic_id)}: expected exactly one " <>
              "presentation descriptor, found none"
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

  defp find_layout_child_by_semantic_id(children, semantic_id) do
    Enum.find_value(children, &find_layout_by_semantic_id(&1, semantic_id))
  end

  defp unique_semantic_entry(definition, segments) do
    case Semantic.find_unique(definition, segments) do
      :not_found -> {:error, :not_found}
      {:ok, %Semantic.Entry{kind: :unsupported}} -> {:error, :unsupported}
      {:ok, %Semantic.Entry{} = entry} -> {:ok, entry}
      {:ambiguous, count} -> ambiguous_reference!(segments, count, nil)
    end
  end

  defp semantic_index(%Semantic.Entry{kind: :object} = entry) do
    entry
    |> Semantic.direct_children()
    |> Enum.group_by(& &1.name)
  end

  defp unique_child!(semantic_index, name, expected_kind) do
    case Map.get(semantic_index, name, []) do
      [%Semantic.Entry{kind: ^expected_kind} = entry] ->
        entry

      [%Semantic.Entry{kind: found_kind, instance_path: path}] ->
        wrong_kind_reference!(path.segments, expected_kind, found_kind)

      matches ->
        path =
          matches
          |> List.first()
          |> semantic_path_for_error(name)

        ambiguous_reference!(path, length(matches), expected_kind)
    end
  end

  defp semantic_path_for_error(nil, name), do: [name]
  defp semantic_path_for_error(%Semantic.Entry{instance_path: path}, _name), do: path.segments

  defp ambiguous_reference!(segments, count, expected_kind) do
    expected =
      case expected_kind do
        nil -> "one semantic occurrence"
        kind -> "one #{kind} occurrence"
      end

    raise ArgumentError,
          "invalid presentation reference #{inspect(segments)}: expected exactly " <>
            "#{expected}, found #{count}"
  end

  defp wrong_kind_reference!(segments, expected_kind, found_kind) do
    raise ArgumentError,
          "invalid presentation reference #{inspect(segments)}: expected a " <>
            "#{expected_kind} occurrence, found #{found_kind}"
  end
end
