defmodule Formentation.Source.SharedTest do
  use ExUnit.Case, async: true

  alias Formentation.Diagnostic
  alias Formentation.Source.Shared
  alias Formentation.Source.Shared.Context

  describe "the map dialect" do
    test "names the declaration, tags map-source origins, and uses atom property segments" do
      assert Formentation.Source.Map.noun() == "declaration"

      assert Formentation.Source.Map.origin([:properties, "a"]) ==
               {:map_source, [:properties, "a"]}

      assert Formentation.Source.Map.property_segment("a") == [:properties, "a"]
    end
  end

  describe "the json schema dialect" do
    test "names the schema, joins origin pointers, and uses string property segments" do
      assert Formentation.Source.JSONSchema.noun() == "schema"

      assert Formentation.Source.JSONSchema.origin(["properties", "a"]) ==
               {:json_schema, "/properties/a"}

      assert Formentation.Source.JSONSchema.origin([]) == {:json_schema, ""}
      assert Formentation.Source.JSONSchema.property_segment("a") == ["properties", "a"]
    end
  end

  describe "check_depth/1" do
    test "passes at the limit and fails past it, wording the noun from the dialect" do
      ctx = Shared.context(Formentation.Source.Map, max_depth: 2)

      assert Context.check_depth(%{ctx | depth: 2}) == :ok

      assert {:error, %Diagnostic{} = diagnostic} = Context.check_depth(%{ctx | depth: 3})
      assert diagnostic.severity == :error
      assert diagnostic.code == :max_depth_exceeded
      assert diagnostic.message == "declaration exceeds maximum depth of 2"
    end

    test "words the noun from the json schema dialect and joins the origin pointer" do
      ctx = Shared.context(Formentation.Source.JSONSchema, max_depth: 1)
      ctx = %{ctx | depth: 2, source_path: ["properties", "a"]}

      assert {:error, %Diagnostic{} = diagnostic} = Context.check_depth(ctx)
      assert diagnostic.message == "schema exceeds maximum depth of 1"
      assert diagnostic.origin == {:json_schema, "/properties/a"}
      assert diagnostic.template_path == ctx.template_path
    end
  end

  describe "take_budget/1" do
    test "decrements the budget and then reports exhaustion" do
      ctx = Shared.context(Formentation.Source.JSONSchema, max_nodes: 1)

      assert {:ok, ctx} = Context.take_budget(ctx)
      assert ctx.nodes_left == 0

      assert {:error, %Diagnostic{} = diagnostic} = Context.take_budget(ctx)
      assert diagnostic.severity == :error
      assert diagnostic.code == :max_nodes_exceeded
      assert diagnostic.message == "schema node budget exhausted"
    end

    test "words exhaustion with the map noun and passes the raw source path as origin" do
      ctx = Shared.context(Formentation.Source.Map, max_nodes: 0)
      ctx = %{ctx | source_path: [:properties, "a"]}

      assert {:error, %Diagnostic{} = diagnostic} = Context.take_budget(ctx)
      assert diagnostic.message == "declaration node budget exhausted"
      assert diagnostic.origin == {:map_source, [:properties, "a"]}
    end
  end
end
