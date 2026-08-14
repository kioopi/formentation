defmodule Formentation.Definition.Semantic do
  @moduledoc false

  alias Formentation.{Definition, InstancePath, TemplatePath}
  alias Formentation.Definition.Semantic

  defmodule Entry do
    @moduledoc false

    @enforce_keys [:kind, :name, :node, :template_path]
    defstruct [:kind, :name, :node, :template_path]

    @type kind :: :object | :field | :unsupported | :collection

    @type t :: %__MODULE__{
            kind: kind(),
            name: String.t() | nil,
            node:
              Semantic.Object.t()
              | Semantic.Field.t()
              | Semantic.Unsupported.t()
              | Semantic.Collection.t(),
            template_path: TemplatePath.t()
          }
  end

  @type entry :: Entry.t()
  @type unique_result :: {:ok, entry()} | :not_found | {:ambiguous, non_neg_integer()}

  @spec root(Definition.t()) :: entry()
  def root(%Definition{semantic: %Semantic.Object{} = root}) do
    entry(:object, root)
  end

  @spec direct_children(entry()) :: [entry()]
  def direct_children(%Entry{kind: :object, node: %Semantic.Object{} = node}) do
    Enum.map(node.children, &native_child_entry/1)
  end

  def direct_children(%Entry{kind: :collection, node: %Semantic.Collection{item: item}}) do
    [native_child_entry(item)]
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

  @spec collections(Definition.t()) :: [entry()]
  def collections(%Definition{} = definition) do
    definition |> root() |> collection_descendants()
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

  defp find_entry(%Entry{kind: :collection} = entry, [segment | rest])
       when is_integer(segment) and segment >= 0 do
    [item] = direct_children(entry)
    find_entry(item, rest)
  end

  defp find_entry(%Entry{} = entry, [segment | rest]) do
    case Enum.find(direct_children(entry), &(&1.name == segment)) do
      nil -> nil
      child -> find_entry(child, rest)
    end
  end

  defp find_unique_entry(entry, []), do: {:ok, entry}

  defp find_unique_entry(%Entry{kind: :collection} = entry, [segment | rest])
       when is_integer(segment) and segment >= 0 do
    [item] = direct_children(entry)
    find_unique_entry(item, rest)
  end

  # Finalized definitions cannot contain sibling name ambiguity. The explicit
  # ambiguity result keeps query callers defensive around hand-built structs.
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
      %Entry{kind: :collection} = child -> scalar_descendants(child)
      %Entry{kind: :unsupported} -> []
    end)
  end

  defp collection_descendants(%Entry{} = entry) do
    entry
    |> direct_children()
    |> Enum.flat_map(fn
      %Entry{kind: :collection} = child -> [child | collection_descendants(child)]
      %Entry{kind: :object} = child -> collection_descendants(child)
      %Entry{} -> []
    end)
  end

  defp unsupported_descendants(%Entry{} = entry) do
    entry
    |> direct_children()
    |> Enum.flat_map(fn
      %Entry{kind: :unsupported} = child -> [child]
      %Entry{kind: :object} = child -> unsupported_descendants(child)
      %Entry{kind: :collection} = child -> unsupported_descendants(child)
      %Entry{kind: :field} -> []
    end)
  end

  defp native_child_entry(%Semantic.Object{} = node) do
    entry(:object, node)
  end

  defp native_child_entry(%Semantic.Field{} = node) do
    entry(:field, node)
  end

  defp native_child_entry(%Semantic.Unsupported{} = node) do
    entry(:unsupported, node)
  end

  defp native_child_entry(%Semantic.Collection{} = node) do
    entry(:collection, node)
  end

  defp entry(kind, node) do
    %Entry{
      kind: kind,
      name: node.name,
      node: node,
      template_path: node.template_path
    }
  end
end
