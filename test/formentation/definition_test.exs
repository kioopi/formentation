defmodule Formentation.DefinitionTest do
  use ExUnit.Case, async: true

  alias Formentation.{Definition, Definition.Finalizer, NodeId, TemplatePath}
  alias Formentation.Presentation
  alias Formentation.Semantic

  defp template(segments), do: TemplatePath.new!(segments)

  defp root(children) do
    Semantic.Object.new(nil, template([]), children)
  end

  defp object(name, children, opts \\ []) do
    Semantic.Object.new(name, template([name]), children, opts)
  end

  defp nested_field(parent, name, opts \\ []) do
    Semantic.Field.new(name, template([parent, name]), :string, opts)
  end

  defp field(name, opts \\ []) do
    Semantic.Field.new(name, template([name]), :string, opts)
  end

  defp unsupported(name, opts \\ []) do
    Semantic.Unsupported.new(name, template([name]), opts)
  end

  test "native finalization returns format version 3 with semantic and presentation roots" do
    field = field("name")
    semantic = root([field])

    presentation =
      Presentation.Object.new(semantic.id, [
        Presentation.Field.new(field.id, label: "Name")
      ])

    assert {:ok,
            %Definition{
              format_version: 3,
              semantic: ^semantic,
              semantic_index: %Semantic.Index{} = index,
              presentation: ^presentation
            }} = Finalizer.finalize(semantic, presentation)

    assert Map.fetch!(index.by_id, field.id).node == field
    assert Map.fetch!(index.by_template_path, field.template_path).node == field
  end

  test "native semantic fields do not carry presentation facts" do
    keys = Semantic.Field.__struct__() |> Map.from_struct() |> Map.keys()

    refute :label in keys
    refute :help in keys
    refute :widget in keys
    refute :hidden? in keys
    refute :group in keys
    refute :instance_path in keys
  end

  test "native presentation field references do not carry semantic facts" do
    keys = Presentation.Field.__struct__() |> Map.from_struct() |> Map.keys()

    refute :semantic_path in keys
    refute :value_type in keys
    refute :role in keys
    refute :required? in keys
    refute :constraints in keys
    refute :options in keys
    refute :default in keys
    refute :examples in keys
    refute :read_only? in keys
  end

  test "constructors derive layout ids in a distinct namespace" do
    semantic_field = field("name")
    presentation_field = Presentation.Field.new(semantic_field.id)

    assert semantic_field.id == NodeId.from_path(template(["name"]))
    assert presentation_field.semantic_id == semantic_field.id
    assert presentation_field.id == "layout:field:/name"
    refute presentation_field.id == semantic_field.id
  end

  test "finalizer accepts nested object layout and presentation groups" do
    width = nested_field("dimensions", "width")
    height = nested_field("dimensions", "height")
    dimensions = object("dimensions", [width, height])
    serial = field("serial")
    semantic = root([serial, dimensions])

    presentation =
      Presentation.Object.new(semantic.id, [
        Presentation.Field.new(serial.id),
        Presentation.Object.new(dimensions.id, [
          Presentation.Group.new(
            NodeId.group(template(["dimensions"]), "size"),
            [
              Presentation.Field.new(height.id),
              Presentation.Field.new(width.id)
            ]
          )
        ])
      ])

    assert {:ok, %Definition{semantic: ^semantic, presentation: ^presentation}} =
             Finalizer.finalize(semantic, presentation)
  end

  test "duplicate semantic child names return a source diagnostic" do
    first = field("name", origins: [name: {:map_source, [:properties, "name"]}])
    duplicate = field("name", origins: [name: {:map_source, [:properties, "name"]}])
    semantic = root([first, duplicate])

    presentation = Presentation.Object.new(semantic.id, [])

    assert {:error,
            [
              %{
                code: :duplicate_property_name,
                origin: {:map_source, [:properties, "name"]},
                template_path: %TemplatePath{segments: ["name"]}
              }
            ]} = Finalizer.finalize(semantic, presentation)
  end

  test "finalizer raises on dangling field references" do
    semantic = root([field("name")])

    presentation =
      Presentation.Object.new(semantic.id, [
        Presentation.Field.new("/missing")
      ])

    assert_raise ArgumentError, ~r/:dangling_presentation_reference/, fn ->
      Finalizer.finalize(semantic, presentation)
    end
  end

  test "finalizer raises on references to unsupported semantic occurrences" do
    semantic = root([unsupported("attachment")])

    presentation =
      Presentation.Object.new(semantic.id, [
        Presentation.Field.new("/attachment")
      ])

    assert_raise ArgumentError, ~r/:unsupported_presentation_reference/, fn ->
      Finalizer.finalize(semantic, presentation)
    end
  end

  test "finalizer raises on kind-mismatched presentation references" do
    semantic_field = field("name")
    semantic = root([semantic_field])

    presentation =
      Presentation.Object.new(semantic.id, [
        Presentation.Object.new(semantic_field.id, [])
      ])

    assert_raise ArgumentError, ~r/:kind_mismatched_presentation_reference/, fn ->
      Finalizer.finalize(semantic, presentation)
    end
  end

  test "finalizer raises on duplicate semantic ids" do
    semantic = root([field("a", id: "/same"), field("b", id: "/same")])
    presentation = Presentation.Object.new(semantic.id, [])

    assert_raise ArgumentError, ~r/:duplicate_semantic_id/, fn ->
      Finalizer.finalize(semantic, presentation)
    end
  end

  test "finalizer raises on invalid semantic child template paths" do
    semantic = root([field("a"), field("b", id: "/b", origins: [], constraints: %{})])
    [a, b] = semantic.children
    semantic = %{semantic | children: [a, %{b | template_path: a.template_path}]}
    presentation = Presentation.Object.new(semantic.id, [])

    assert_raise ArgumentError, ~r/:invalid_semantic_template_path/, fn ->
      Finalizer.finalize(semantic, presentation)
    end
  end

  test "finalizer raises on non-root semantic roots" do
    semantic = Semantic.Object.new("nested", template(["nested"]), [])
    presentation = Presentation.Object.new("/", [])

    assert_raise ArgumentError, ~r/:invalid_semantic_root/, fn ->
      Finalizer.finalize(semantic, presentation)
    end
  end

  test "finalizer raises on invalid semantic children" do
    semantic = root([%{name: "not_a_semantic_node"}])
    presentation = Presentation.Object.new("/", [])

    assert_raise ArgumentError, ~r/:invalid_semantic_child/, fn ->
      Finalizer.finalize(semantic, presentation)
    end
  end

  test "finalizer raises on semantic children without string names" do
    semantic = root([%{field("name") | name: nil}])
    presentation = Presentation.Object.new("/", [])

    assert_raise ArgumentError, ~r/:invalid_semantic_name/, fn ->
      Finalizer.finalize(semantic, presentation)
    end
  end

  test "duplicate child diagnostics fall back when malformed children have no origin" do
    semantic = root([%{name: "a"}, %{name: "a"}])
    presentation = Presentation.Object.new("/", [])

    assert {:error,
            [
              %{
                code: :duplicate_property_name,
                origin: nil,
                template_path: %TemplatePath{segments: []}
              }
            ]} = Finalizer.finalize(semantic, presentation)
  end

  test "nested duplicate child diagnostics halt parent semantic collection" do
    child = object("nested", [nested_field("nested", "a"), nested_field("nested", "a")])
    semantic = root([child])
    presentation = Presentation.Object.new("/", [])

    assert {:error,
            [
              %{
                code: :duplicate_property_name,
                template_path: %TemplatePath{segments: ["nested", "a"]}
              }
            ]} =
             Finalizer.finalize(semantic, presentation)
  end

  test "finalizer raises on duplicate layout ids" do
    a = field("a")
    b = field("b")
    semantic = root([a, b])

    presentation =
      Presentation.Object.new(semantic.id, [
        Presentation.Field.new(a.id, id: "/duplicate"),
        Presentation.Field.new(b.id, id: "/duplicate")
      ])

    assert_raise ArgumentError, ~r/:duplicate_layout_id/, fn ->
      Finalizer.finalize(semantic, presentation)
    end
  end

  test "finalizer raises on duplicate presentation references" do
    a = field("a")
    semantic = root([a])

    presentation =
      Presentation.Object.new(semantic.id, [
        Presentation.Field.new(a.id, id: "layout:field:a:one"),
        Presentation.Field.new(a.id, id: "layout:field:a:two")
      ])

    assert_raise ArgumentError, ~r/:duplicate_presentation_reference/, fn ->
      Finalizer.finalize(semantic, presentation)
    end
  end

  test "finalizer raises on missing built-in presentation references" do
    shown = field("shown")
    missing = field("missing")
    semantic = root([shown, missing])

    presentation =
      Presentation.Object.new(semantic.id, [
        Presentation.Field.new(shown.id)
      ])

    assert_raise ArgumentError, ~r/:missing_presentation_reference/, fn ->
      Finalizer.finalize(semantic, presentation)
    end
  end

  test "finalizer raises on invalid presentation children" do
    semantic = root([])
    presentation = Presentation.Object.new(semantic.id, [%{id: "not_a_presentation_node"}])

    assert_raise ArgumentError, ~r/:invalid_presentation_child/, fn ->
      Finalizer.finalize(semantic, presentation)
    end
  end
end
