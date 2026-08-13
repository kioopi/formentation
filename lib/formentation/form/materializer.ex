defmodule Formentation.Form.Materializer do
  @moduledoc """
  Rebuilds the candidate JSON instance from the original data and one
  transition's operations (D-009). Declared children rebuild from
  operations; undeclared keys and unsupported nodes' values are
  preserved from the original. Nested-object presence is content-derived
  (D-026). While any operation is invalid, there is no candidate at all
  (D-012).
  """

  alias Formentation.{Definition, InstancePath}
  alias Formentation.Definition.Semantic
  alias Formentation.Form.FieldState

  @doc """
  `{:ok, candidate}` for `operations` applied over `original`, or
  `:none` while any operation is `{:invalid, _}` (D-012).

      iex> {:ok, definition, []} =
      ...>   Formentation.compile(
      ...>     %{kind: :object, properties: [{"age", %{kind: :integer}}]},
      ...>     adapter: Formentation.Source.Map
      ...>   )
      iex> operations = %{Formentation.InstancePath.new!(["age"]) => {:set, 42}}
      iex> Formentation.Form.Materializer.materialize(definition, %{}, operations)
      {:ok, %{"age" => 42}}
  """
  @spec materialize(Definition.t(), map(), %{InstancePath.t() => FieldState.operation()}) ::
          {:ok, map()} | :none
  def materialize(%Definition{} = definition, original, operations) when is_map(original) do
    invalid? =
      Enum.any?(operations, fn {_path, operation} -> match?({:invalid, _}, operation) end)

    if invalid? do
      :none
    else
      root = Semantic.root(definition)
      {:ok, materialize_object(root, original, InstancePath.new!([]), operations)}
    end
  end

  # Declared children rebuild from operations; keys the definition does
  # not describe are preserved from the original data, as are unsupported
  # nodes' values (preserve inactive data — D-009).
  defp materialize_object(%Semantic.Entry{kind: :object} = entry, original, path, operations) do
    original = if is_map(original), do: original, else: %{}

    {declared_result, declared_names} =
      materialize_children(entry, original, path, operations)

    original
    |> Map.drop(MapSet.to_list(declared_names))
    |> Map.merge(declared_result)
  end

  # Content-derived presence (D-026): a data-nesting object is emitted only
  # when recursive materialization leaves at least one declared or preserved
  # key. `required?` is a validation constraint and never manufactures an
  # object; presence is decided only after declared-child materialization and
  # original unknown/unsupported-data preservation have run. The explicit
  # `:absent | {:present, map()}` result is the extension point for future
  # collections, branches, and group-level presence transport — do not
  # collapse it into an `if value == %{}` at the call site.
  defp materialize_nested_object(entry, original, path, operations) do
    case materialize_object(entry, original, path, operations) do
      map when map_size(map) == 0 -> :absent
      map -> {:present, map}
    end
  end

  defp materialize_children(%Semantic.Entry{kind: :object} = entry, original, path, operations) do
    entry
    |> Semantic.direct_children()
    |> Enum.reduce({%{}, MapSet.new()}, fn child, {acc, declared} ->
      materialize_child(
        child,
        original,
        InstancePath.child(path, child.name),
        operations,
        acc,
        declared
      )
    end)
  end

  defp materialize_child(
         %Semantic.Entry{kind: :field, name: name},
         original,
         path,
         operations,
         acc,
         declared
       ) do
    declared = MapSet.put(declared, name)

    case Map.get(operations, path, :keep) do
      {:set, value} -> {Map.put(acc, name, value), declared}
      :unset -> {acc, declared}
      :keep -> {put_original(acc, original, name), declared}
    end
  end

  defp materialize_child(
         %Semantic.Entry{kind: :object, name: name} = entry,
         original,
         path,
         operations,
         acc,
         declared
       ) do
    # Claim the name even when the object is absent, so an originally
    # present group is not accidentally restored by unknown-key
    # preservation in `materialize_object/4` (D-026).
    declared = MapSet.put(declared, name)

    case materialize_nested_object(entry, Map.get(original, name, %{}), path, operations) do
      {:present, value} -> {Map.put(acc, name, value), declared}
      :absent -> {acc, declared}
    end
  end

  defp materialize_child(
         %Semantic.Entry{kind: :unsupported, name: name},
         original,
         _path,
         _operations,
         acc,
         declared
       ) do
    {put_original(acc, original, name), MapSet.put(declared, name)}
  end

  defp put_original(acc, original, name) do
    case Map.fetch(original, name) do
      {:ok, value} -> Map.put(acc, name, value)
      :error -> acc
    end
  end
end
