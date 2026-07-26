defmodule Formentation.Semantic do
  @moduledoc false

  alias Formentation.{Definition, InstancePath, Node, TemplatePath}

  defmodule Entry do
    @moduledoc false

    @enforce_keys [:kind, :name, :node, :instance_path, :template_path]
    defstruct [:kind, :name, :node, :instance_path, :template_path]

    @type kind :: :object | :field | :unsupported

    @type t :: %__MODULE__{
            kind: kind(),
            name: String.t() | nil,
            node: Node.t(),
            instance_path: InstancePath.t(),
            template_path: TemplatePath.t()
          }
  end

  @type entry :: Entry.t()
  @type unique_result :: {:ok, entry()} | :not_found | {:ambiguous, non_neg_integer()}

  @spec root(Definition.t()) :: entry()
  def root(%Definition{root: %Node.Group{} = root}) do
    entry(:object, root, %InstancePath{segments: []})
  end

  @spec direct_children(entry()) :: [entry()]
  def direct_children(%Entry{kind: :object, node: %Node.Group{} = node, instance_path: path}) do
    node.children
    |> Enum.with_index()
    |> Enum.flat_map(fn {child, index} -> direct_child_entries(child, path, [index]) end)
    |> Enum.sort_by(fn {entry, reversed_index_path} ->
      {declaration_order(entry.node), Enum.reverse(reversed_index_path)}
    end)
    |> Enum.map(fn {entry, _reversed_index_path} -> entry end)
  end

  def direct_children(%Entry{}), do: []

  @spec fields(Definition.t()) :: [entry()]
  def fields(%Definition{} = definition) do
    definition |> root() |> scalar_descendants()
  end

  @spec unsupported(Definition.t()) :: [entry()]
  def unsupported(%Definition{} = definition) do
    definition |> root() |> unsupported_descendants()
  end

  @spec find(Definition.t(), [InstancePath.segment()]) :: entry() | nil
  def find(%Definition{} = definition, segments) when is_list(segments) do
    %InstancePath{segments: segments} = InstancePath.new!(segments)
    find_entry(root(definition), segments)
  end

  @spec find_unique(Definition.t(), [InstancePath.segment()]) :: unique_result()
  def find_unique(%Definition{} = definition, segments) when is_list(segments) do
    %InstancePath{segments: segments} = InstancePath.new!(segments)
    find_unique_entry(root(definition), segments)
  end

  defp find_entry(entry, []), do: entry

  defp find_entry(%Entry{} = entry, [segment | rest]) do
    case Enum.find(direct_children(entry), &(&1.name == segment)) do
      nil -> nil
      child -> find_entry(child, rest)
    end
  end

  defp find_unique_entry(entry, []), do: {:ok, entry}

  defp find_unique_entry(%Entry{} = entry, [segment | rest]) do
    case Enum.filter(direct_children(entry), &(&1.name == segment)) do
      [] -> :not_found
      [child] -> find_unique_entry(child, rest)
      matches -> {:ambiguous, length(matches)}
    end
  end

  defp scalar_descendants(%Entry{} = entry) do
    entry
    |> direct_children()
    |> Enum.flat_map(fn
      %Entry{kind: :field} = child -> [child]
      %Entry{kind: :object} = child -> scalar_descendants(child)
      %Entry{kind: :unsupported} -> []
    end)
  end

  defp unsupported_descendants(%Entry{} = entry) do
    entry
    |> direct_children()
    |> Enum.flat_map(fn
      %Entry{kind: :unsupported} = child -> [child]
      %Entry{kind: :object} = child -> unsupported_descendants(child)
      %Entry{kind: :field} -> []
    end)
  end

  defp direct_child_entries(
         %Node.Group{nests_data?: false, children: children},
         parent_path,
         reversed_index_path
       ) do
    children
    |> Enum.with_index()
    |> Enum.flat_map(fn {child, child_index} ->
      direct_child_entries(child, parent_path, [child_index | reversed_index_path])
    end)
  end

  defp direct_child_entries(%Node.Group{nests_data?: true} = node, parent_path, index) do
    path = child_path(parent_path, node.name)
    [{entry(:object, node, path), index}]
  end

  defp direct_child_entries(%Node.Field{} = node, parent_path, index) do
    path = child_path(parent_path, node.name)
    [{entry(:field, node, path), index}]
  end

  defp direct_child_entries(%Node.Unsupported{} = node, parent_path, index) do
    path = child_path(parent_path, node.name)
    [{entry(:unsupported, node, path), index}]
  end

  defp entry(kind, node, instance_path) do
    %Entry{
      kind: kind,
      name: node.name,
      node: node,
      instance_path: instance_path,
      template_path: node.template_path
    }
  end

  defp child_path(%InstancePath{segments: segments}, name) when is_binary(name) do
    InstancePath.new!(segments ++ [name])
  end

  defp declaration_order(%{declaration_order: order}) when is_integer(order), do: order
  defp declaration_order(_node), do: :infinity
end
