defmodule Formentation.Info.Presentation do
  @moduledoc """
  Typed presentation traversal descriptors returned by `Formentation.Info`.

  These structs describe the current layout query contract over a compiled
  definition. They are descriptors, not stored definition state: the current
  implementation derives them from the compatibility mixed tree on demand.
  """

  alias Formentation.{Definition, InstancePath, Node, Semantic}

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

  defp descriptor(%Semantic.Entry{kind: :object} = entry, definition),
    do: object(entry, definition)

  defp descriptor(%Semantic.Entry{kind: :field} = entry, _definition), do: field(entry)

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
