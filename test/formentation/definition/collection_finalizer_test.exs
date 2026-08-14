defmodule Formentation.Definition.CollectionFinalizerTest do
  use ExUnit.Case, async: true

  alias Formentation.Definition.{Finalizer, Presentation, Semantic}
  alias Formentation.{Diagnostic, NodeId, TemplatePath}

  defp collection(opts \\ []) do
    path = TemplatePath.new!(["measurements"])
    item = Keyword.get(opts, :item, Semantic.Field.new(nil, TemplatePath.item(path), :number))

    Semantic.Collection.new("measurements", path, item,
      constraints: Keyword.get(opts, :constraints, %{min_items: 1, max_items: 10}),
      origins: [
        min_items: {:map_source, [:properties, "measurements", :min_items]},
        max_items: {:map_source, [:properties, "measurements", :max_items]}
      ]
    )
  end

  defp finalize(collection) do
    root = Semantic.Object.new(nil, TemplatePath.new!([]), [collection])
    root_id = NodeId.from_path(TemplatePath.new!([]))

    item =
      if match?(%Semantic.Unsupported{}, collection.item),
        do: nil,
        else: Presentation.Field.new(collection.item.id)

    presentation =
      Presentation.Object.new(root_id, [Presentation.Collection.new(collection.id, item)])

    Finalizer.finalize(root, presentation)
  end

  test "a valid collection finalizes and indexes its item" do
    assert {:ok, definition} = finalize(collection())
    assert definition.format_version == 4
    assert %{kind: :collection} = definition.semantic_index.by_id["/measurements"]
    assert %{kind: :field} = definition.semantic_index.by_id["/measurements/~3"]
  end

  test "invalid cardinality returns a diagnostic at its origin" do
    assert {:error, [%Diagnostic{code: :invalid_cardinality, origin: origin}]} =
             finalize(collection(constraints: %{min_items: 4, max_items: 2}))

    assert origin == {:map_source, [:properties, "measurements", :max_items]}
  end

  test "a named item template raises" do
    path = TemplatePath.new!(["measurements"])

    assert_raise ArgumentError, ~r/invalid_collection_item_name/, fn ->
      finalize(collection(item: Semantic.Field.new("item", TemplatePath.item(path), :number)))
    end
  end
end
