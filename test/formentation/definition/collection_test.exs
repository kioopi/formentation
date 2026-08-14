defmodule Formentation.Definition.CollectionTest do
  use ExUnit.Case, async: true

  alias Formentation.Definition.Semantic
  alias Formentation.TemplatePath

  describe "Semantic.Collection.new/4" do
    test "builds a collection node with an anonymous item template" do
      path = TemplatePath.new!(["measurements"])
      item = Semantic.Field.new(nil, TemplatePath.item(path), :number)

      collection =
        Semantic.Collection.new("measurements", path, item,
          required?: true,
          constraints: %{min_items: 1, max_items: 10},
          origins: [kind: {:map_source, [:properties, "measurements", :kind]}]
        )

      assert collection.id == "/measurements"
      assert collection.name == "measurements"
      assert collection.item == item
      assert collection.required?
      assert collection.constraints == %{min_items: 1, max_items: 10}
    end

    test "the anonymous item template encodes :item as ~3 in its node id" do
      path = TemplatePath.new!(["measurements"])
      item = Semantic.Field.new(nil, TemplatePath.item(path), :number)

      assert item.id == "/measurements/~3"
      assert item.name == nil
    end

    test "anonymous Unsupported nodes are constructible" do
      path = TemplatePath.new!(["attachments"])
      item = Semantic.Unsupported.new(nil, TemplatePath.item(path))
      assert item.name == nil
      assert item.id == "/attachments/~3"
    end

    test "ordinary named constructors still work" do
      path = TemplatePath.new!(["name"])
      assert %Semantic.Field{name: "name"} = Semantic.Field.new("name", path, :string)
      assert %Semantic.Unsupported{name: "x"} = Semantic.Unsupported.new("x", path)
    end
  end

  describe "Semantic traversal over collections" do
    defp definition_with(collection) do
      root = Semantic.Object.new(nil, TemplatePath.new!([]), [collection])
      %Formentation.Definition{semantic: root, semantic_index: nil, presentation: nil}
    end

    defp scalar_collection do
      path = TemplatePath.new!(["measurements"])
      item = Semantic.Field.new(nil, TemplatePath.item(path), :number)
      Semantic.Collection.new("measurements", path, item)
    end

    defp object_collection do
      path = TemplatePath.new!(["addresses"])
      item_path = TemplatePath.item(path)

      item =
        Semantic.Object.new(nil, item_path, [
          Semantic.Field.new("street", TemplatePath.child(item_path, "street"), :string),
          Semantic.Unsupported.new("photo", TemplatePath.child(item_path, "photo"))
        ])

      Semantic.Collection.new("addresses", path, item)
    end

    test "direct_children of a collection is the single anonymous item entry" do
      definition = definition_with(scalar_collection())
      collection_entry = Semantic.find(definition, ["measurements"])

      assert collection_entry.kind == :collection

      assert [%Semantic.Entry{kind: :field, name: nil} = item] =
               Semantic.direct_children(collection_entry)

      assert item.template_path.segments == ["measurements", :item]
    end

    test "integer instance segment resolves to the item template" do
      definition = definition_with(scalar_collection())

      assert %Semantic.Entry{kind: :field, name: nil} =
               Semantic.find(definition, ["measurements", 0])

      assert %Semantic.Entry{kind: :field, name: nil} =
               Semantic.find(definition, ["measurements", 7])

      assert {:ok, %Semantic.Entry{kind: :field}} =
               Semantic.find_unique(definition, ["measurements", 3])
    end

    test "integer segments resolve through object items to named children" do
      definition = definition_with(object_collection())

      assert %Semantic.Entry{kind: :field, name: "street"} =
               Semantic.find(definition, ["addresses", 2, "street"])
    end

    test "integer segments never match object children" do
      definition = definition_with(object_collection())
      assert Semantic.find(definition, [0]) == nil
      assert Semantic.find_unique(definition, [0]) == :not_found
    end

    test "fields and unsupported descend through collections" do
      scalar = definition_with(scalar_collection())
      assert [%Semantic.Entry{kind: :field, name: nil}] = Semantic.fields(scalar)

      object = definition_with(object_collection())
      assert [%Semantic.Entry{name: "street"}] = Semantic.fields(object)
      assert [%Semantic.Entry{kind: :unsupported, name: "photo"}] = Semantic.unsupported(object)
    end
  end
end
