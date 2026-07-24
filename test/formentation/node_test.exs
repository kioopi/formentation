defmodule Formentation.NodeTest do
  use ExUnit.Case, async: true

  alias Formentation.{Node, TemplatePath}

  @path %TemplatePath{segments: ["name"]}

  describe "Node.Field" do
    test "constructs with defaults for optional attributes" do
      field = %Node.Field{id: "/name", name: "name", value_type: :string, template_path: @path}

      assert field.required? == false
      assert field.constraints == %{}
      assert field.origins == []
    end

    test "requires a value_type" do
      assert_raise ArgumentError, ~r/value_type/, fn ->
        struct!(Node.Field, id: "/name", name: "name", template_path: @path)
      end
    end

    test "has no children key" do
      field = %Node.Field{id: "/name", name: "name", value_type: :string, template_path: @path}
      refute Map.has_key?(field, :children)
    end
  end

  describe "Node.Group" do
    test "requires an explicit nests_data? flavor" do
      assert_raise ArgumentError, ~r/nests_data\?/, fn ->
        struct!(Node.Group, id: "/", template_path: %TemplatePath{segments: []})
      end
    end

    test "carries no field-only attributes" do
      group = %Node.Group{id: "/", template_path: %TemplatePath{segments: []}, nests_data?: true}

      refute Map.has_key?(group, :value_type)
      refute Map.has_key?(group, :widget)
      refute Map.has_key?(group, :constraints)
      assert group.children == []
    end
  end

  describe "Node.Unsupported" do
    test "keeps only identity, requiredness, and origins" do
      node = %Node.Unsupported{id: "/gadget", name: "gadget", template_path: @path}

      assert node.required? == false
      refute Map.has_key?(node, :children)
      refute Map.has_key?(node, :value_type)
    end
  end
end
