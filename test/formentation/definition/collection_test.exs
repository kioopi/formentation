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
end
