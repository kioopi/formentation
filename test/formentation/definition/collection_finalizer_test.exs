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

  defp semantic_root(collection) do
    Semantic.Object.new(nil, TemplatePath.new!([]), [collection])
  end

  defp root_presentation(children) do
    Presentation.Object.new(NodeId.from_path(TemplatePath.new!([])), children)
  end

  defp presentation_item(%Semantic.Unsupported{}), do: nil
  defp presentation_item(%Semantic.Field{} = item), do: Presentation.Field.new(item.id)

  defp presentation_item(%Semantic.Object{} = item) do
    children =
      for %Semantic.Field{} = child <- item.children, do: Presentation.Field.new(child.id)

    Presentation.Object.new(item.id, children)
  end

  defp presentation_item(%Semantic.Collection{} = item) do
    Presentation.Collection.new(item.id, presentation_item(item.item))
  end

  defp finalize(collection) do
    presentation =
      root_presentation([
        Presentation.Collection.new(collection.id, presentation_item(collection.item))
      ])

    Finalizer.finalize(semantic_root(collection), presentation)
  end

  defp object_item do
    item_path = TemplatePath.item(TemplatePath.new!(["measurements"]))

    Semantic.Object.new(nil, item_path, [
      Semantic.Field.new("street", TemplatePath.child(item_path, "street"), :string)
    ])
  end

  test "a valid collection finalizes and indexes its item" do
    assert {:ok, definition} = finalize(collection())
    assert definition.format_version == 4
    assert %{kind: :collection} = definition.semantic_index.by_id["/measurements"]
    assert %{kind: :field} = definition.semantic_index.by_id["/measurements/~3"]
  end

  test "all three item-template shapes finalize" do
    item_path = TemplatePath.item(TemplatePath.new!(["measurements"]))

    assert {:ok, _} = finalize(collection())
    assert {:ok, _} = finalize(collection(item: object_item()))
    assert {:ok, _} = finalize(collection(item: Semantic.Unsupported.new(nil, item_path)))
  end

  test "a nested collection item template finalizes (recursive model, D-053)" do
    outer_path = TemplatePath.new!(["measurements"])
    inner_path = TemplatePath.item(outer_path)

    inner =
      Semantic.Collection.new(
        nil,
        inner_path,
        Semantic.Field.new(nil, TemplatePath.item(inner_path), :number)
      )

    assert {:ok, definition} = finalize(collection(item: inner))
    assert %{kind: :collection} = definition.semantic_index.by_id["/measurements/~3"]
    assert %{kind: :field} = definition.semantic_index.by_id["/measurements/~3/~3"]
  end

  test "an object item's presentation must cover its fields too" do
    coll = collection(item: object_item())

    # item descriptor deliberately omits the street field reference
    presentation =
      root_presentation([
        Presentation.Collection.new(coll.id, Presentation.Object.new(coll.item.id, []))
      ])

    assert_raise ArgumentError, ~r/missing_presentation_reference/, fn ->
      Finalizer.finalize(semantic_root(coll), presentation)
    end
  end

  # -- returned diagnostics (D-052) -----------------------------------

  test "negative and non-integer bounds return :invalid_cardinality diagnostics" do
    for bad <- [%{min_items: -1}, %{max_items: "10"}, %{min_items: 1.5}] do
      assert {:error, [%Diagnostic{code: :invalid_cardinality, severity: :error} = d]} =
               finalize(collection(constraints: bad))

      assert d.template_path.segments == ["measurements"]
    end
  end

  test "invalid cardinality returns a diagnostic at its bound's origin" do
    assert {:error, [%Diagnostic{code: :invalid_cardinality, origin: origin}]} =
             finalize(collection(constraints: %{min_items: 4, max_items: 2}))

    assert origin == {:map_source, [:properties, "measurements", :max_items]}
  end

  # -- raised invariants (broken adapter) ------------------------------

  test "a named item template raises" do
    path = TemplatePath.new!(["measurements"])

    assert_raise ArgumentError, ~r/invalid_collection_item_name/, fn ->
      finalize(collection(item: Semantic.Field.new("item", TemplatePath.item(path), :number)))
    end
  end

  test "an item template off the :item path raises" do
    bad_item = Semantic.Field.new(nil, TemplatePath.new!(["elsewhere", :item]), :number)

    assert_raise ArgumentError, ~r/invalid_semantic_template_path/, fn ->
      finalize(collection(item: bad_item))
    end
  end

  test "constraint keys outside the compiled subset raise" do
    assert_raise ArgumentError, ~r/invalid_collection_constraints/, fn ->
      finalize(collection(constraints: %{unique_items: true}))
    end
  end

  test "a non-descriptor in the presentation item slot raises" do
    coll = collection()

    presentation =
      root_presentation([Presentation.Collection.new(coll.id, :not_a_descriptor)])

    assert_raise ArgumentError, ~r/invalid_presentation_child/, fn ->
      Finalizer.finalize(semantic_root(coll), presentation)
    end
  end

  test "an anonymous node directly under an object still raises" do
    # The ordinary object-child invariant must NOT be weakened by the
    # collection item-template exception.
    root =
      Semantic.Object.new(nil, TemplatePath.new!([]), [
        Semantic.Field.new(nil, TemplatePath.new!(["x"]), :string)
      ])

    assert_raise ArgumentError, ~r/invalid_semantic_name/, fn ->
      Finalizer.finalize(root, root_presentation([]))
    end
  end
end
