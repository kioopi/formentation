defmodule Formentation.Source.SharedTest do
  use ExUnit.Case, async: true

  alias Formentation.Definition.{Presentation, Semantic}
  alias Formentation.Diagnostic
  alias Formentation.Source.Shared
  alias Formentation.Source.Shared.Build
  alias Formentation.Source.Shared.Context
  alias Formentation.TemplatePath

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

  describe "enter_property/2" do
    test "descends one map property: depth, template path, atom-keyed source path" do
      ctx = Shared.context(Formentation.Source.Map, [])
      child = Context.enter_property(ctx, "user")

      assert child.depth == 1
      assert child.template_path == TemplatePath.new!(["user"])
      assert child.source_path == [:properties, "user"]
      assert child.dialect == Formentation.Source.Map
      assert child.nodes_left == ctx.nodes_left
      assert child.max_depth == ctx.max_depth
    end

    test "descends one json schema property: string-keyed source path" do
      ctx = Shared.context(Formentation.Source.JSONSchema, [])
      child = Context.enter_property(ctx, "user")

      assert child.depth == 1
      assert child.template_path == TemplatePath.new!(["user"])
      assert child.source_path == ["properties", "user"]
    end

    test "nests, appending to the paths it was given" do
      ctx = Shared.context(Formentation.Source.JSONSchema, [])
      grandchild = ctx |> Context.enter_property("user") |> Context.enter_property("name")

      assert grandchild.depth == 2
      assert grandchild.template_path == TemplatePath.new!(["user", "name"])
      assert grandchild.source_path == ["properties", "user", "properties", "name"]
    end

    test "carries accumulated diagnostics into the child" do
      diagnostic = %Diagnostic{
        severity: :warning,
        code: :example,
        message: "example",
        origin: nil,
        template_path: TemplatePath.new!([])
      }

      ctx =
        Formentation.Source.Map
        |> Shared.context([])
        |> Context.add_diagnostic(diagnostic)

      assert Context.enter_property(ctx, "user").diagnostics == [diagnostic]
    end
  end

  describe "add_diagnostic/2" do
    test "prepends, so accumulation is reverse order" do
      first = %Diagnostic{
        severity: :warning,
        code: :first,
        message: "first",
        origin: nil,
        template_path: TemplatePath.new!([])
      }

      second = %{first | code: :second, message: "second"}

      ctx =
        Formentation.Source.Map
        |> Shared.context([])
        |> Context.add_diagnostic(first)
        |> Context.add_diagnostic(second)

      assert Enum.map(ctx.diagnostics, & &1.code) == [:second, :first]
    end
  end

  describe "finalize/1" do
    test "produces a definition carrying the build's diagnostics and validation plan" do
      root = TemplatePath.new!([])
      field = Semantic.Field.new("a", TemplatePath.child(root, "a"), :string)
      semantic = Semantic.Object.new(nil, root, [field])
      presentation = Presentation.Object.new(semantic.id, [Presentation.Field.new(field.id)])

      warning = %Diagnostic{
        severity: :warning,
        code: :example,
        message: "example",
        origin: nil,
        template_path: root
      }

      build = %Build{
        semantic: semantic,
        presentation: presentation,
        diagnostics: [warning],
        validation: :a_plan
      }

      assert {:ok, definition, diagnostics} = Shared.finalize(build)
      assert diagnostics == [warning]
      assert definition.diagnostics == [warning]
      assert definition.validation == :a_plan
      assert definition.semantic == semantic
      assert definition.presentation == presentation
      assert %Semantic.Index{} = definition.semantic_index
    end

    test "returns finalizer errors as diagnostics instead of raising" do
      root = TemplatePath.new!([])
      field = Semantic.Field.new("a", TemplatePath.child(root, "a"), :string)
      semantic = Semantic.Object.new(nil, root, [field, field])
      presentation = Presentation.Object.new(semantic.id, [Presentation.Field.new(field.id)])
      build = %Build{semantic: semantic, presentation: presentation, diagnostics: []}

      assert {:error, [%Diagnostic{} = diagnostic]} = Shared.finalize(build)
      assert diagnostic.severity == :error
      assert diagnostic.code == :duplicate_property_name
    end
  end
end
