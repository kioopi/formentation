defmodule Formentation.InfoTest do
  use ExUnit.Case, async: true

  alias Formentation.Definition.{Finalizer, Presentation, Semantic}
  alias Formentation.{Info, NodeId, TemplatePath}

  doctest Formentation.Info

  # A hand-built native definition: proves Info reads split structs
  # without going through a source adapter.
  defp definition do
    name =
      Semantic.Field.new("name", %TemplatePath{segments: ["name"]}, :string,
        role: :text,
        required?: true,
        origins: [role: {:inference, :text_role}]
      )

    voltage =
      Semantic.Field.new("voltage", %TemplatePath{segments: ["electrical", "voltage"]}, :integer,
        role: :integer
      )

    legacy =
      Semantic.Unsupported.new("legacy", %TemplatePath{segments: ["electrical", "legacy"]},
        required?: true
      )

    electrical =
      Semantic.Object.new("electrical", %TemplatePath{segments: ["electrical"]}, [
        voltage,
        legacy
      ])

    gadget = Semantic.Unsupported.new("gadget", %TemplatePath{segments: ["gadget"]})

    semantic = Semantic.Object.new(nil, %TemplatePath{segments: []}, [name, electrical, gadget])

    presentation =
      Presentation.Object.new("/", [
        Presentation.Field.new("/name", label: "Name"),
        Presentation.Object.new("/electrical", [
          Presentation.Group.new(
            NodeId.group(%TemplatePath{segments: ["electrical"]}, "power"),
            [Presentation.Field.new("/electrical/voltage")],
            label: "Power"
          )
        ])
      ])

    {:ok, definition} = Finalizer.finalize(semantic, presentation)
    definition
  end

  test "fields/1 returns exactly the field nodes, in tree order" do
    assert ["name", "voltage"] == definition() |> Info.fields() |> Enum.map(& &1.name)
  end

  test "node_at/2 descends data groups and looks through presentational groups" do
    assert %Semantic.Field{id: "/electrical/voltage"} =
             Info.node_at(definition(), ["electrical", "voltage"])
  end

  test "node_at/2 finds unsupported nodes" do
    assert %Semantic.Unsupported{id: "/gadget"} = Info.node_at(definition(), ["gadget"])
  end

  test "node/2 finds any node by id, including presentational groups" do
    assert %Presentation.Group{} = Info.node(definition(), "/electrical#power")
  end

  test "role/2, origins/2, and required?/2 read per-kind nodes" do
    assert Info.role(definition(), ["name"]) == :text
    assert Info.origins(definition(), ["name"]) == [role: {:inference, :text_role}]
    assert Info.required?(definition(), ["name"])
    refute Info.required?(definition(), ["electrical", "voltage"])
  end

  test "role/2 is nil for groups and missing paths, origins/2 empty for missing paths" do
    assert Info.role(definition(), ["electrical"]) == nil
    assert Info.role(definition(), ["missing"]) == nil
    assert Info.origins(definition(), ["missing"]) == []
  end

  test "origins/2 returns only semantic origins for unsupported paths" do
    assert Info.origins(definition(), ["gadget"]) == []
  end

  test "origins/2 works on semantic-only hand-built definitions" do
    field =
      Semantic.Field.new("name", %TemplatePath{segments: ["name"]}, :string,
        origins: [role: {:inference, :text_role}]
      )

    definition = %Formentation.Definition{
      semantic: Semantic.Object.new(nil, %TemplatePath{segments: []}, [field]),
      presentation: nil
    }

    assert Info.origins(definition, ["name"]) == [role: {:inference, :text_role}]
  end

  test "semantic_kind/2 classifies paths without accepting presentation group IDs" do
    assert Info.semantic_kind(definition(), []) == :object
    assert Info.semantic_kind(definition(), ["name"]) == :field
    assert Info.semantic_kind(definition(), ["electrical"]) == :object
    assert Info.semantic_kind(definition(), ["electrical", "legacy"]) == :unsupported
    assert Info.semantic_kind(definition(), ["electrical", "power"]) == nil
    assert Info.semantic_kind(definition(), ["missing"]) == nil
  end

  test "semantic_kind/2 raises on ambiguous hand-built semantic paths" do
    semantic =
      Semantic.Object.new(nil, %TemplatePath{segments: []}, [
        Semantic.Field.new("name", %TemplatePath{segments: ["name"]}, :string),
        Semantic.Field.new("name", %TemplatePath{segments: ["name"]}, :string, id: "/other-name")
      ])

    definition = %Formentation.Definition{semantic: semantic}

    assert_raise ArgumentError, ~r/ambiguous semantic path \["name"\]: found 2 occurrences/, fn ->
      Info.semantic_kind(definition, ["name"])
    end
  end

  test "semantic_node_index/1 raises on ambiguous hand-built semantic paths" do
    semantic =
      Semantic.Object.new(nil, %TemplatePath{segments: []}, [
        Semantic.Field.new("name", %TemplatePath{segments: ["name"]}, :string),
        Semantic.Field.new("name", %TemplatePath{segments: ["name"]}, :string, id: "/other-name")
      ])

    definition = %Formentation.Definition{semantic: semantic}

    assert_raise ArgumentError, ~r/ambiguous semantic path \["name"\]: found 2 occurrences/, fn ->
      Info.semantic_node_index(definition)
    end
  end

  test "node/2 returns nil when a definition has no presentation tree" do
    definition = %Formentation.Definition{
      semantic_index: %Semantic.Index{},
      presentation: nil
    }

    assert Info.node(definition, "/missing") == nil
  end

  test "unsupported_nodes/1 returns unsupported nodes in declaration order" do
    assert ["gadget", "legacy"] ==
             definition() |> Info.unsupported_nodes() |> Enum.map(& &1.name) |> Enum.sort()

    # order is tree/declaration order: electrical (with nested legacy) precedes gadget
    assert ["legacy", "gadget"] ==
             definition() |> Info.unsupported_nodes() |> Enum.map(& &1.name)
  end

  test "unsupported_nodes/1 preserves node identity fields" do
    [legacy, _gadget] = Info.unsupported_nodes(definition())
    assert %Semantic.Unsupported{id: "/electrical/legacy", required?: true} = legacy
  end

  test "unsupported_nodes/1 is empty when there are none" do
    semantic = Semantic.Object.new(nil, %TemplatePath{segments: []}, [])
    presentation = Presentation.Object.new("/", [])
    {:ok, definition} = Finalizer.finalize(semantic, presentation)

    assert Info.unsupported_nodes(definition) == []
  end

  test "unsupported_nodes_with_paths/1 pairs nodes with instance paths through both group flavors" do
    paths =
      definition()
      |> Info.unsupported_nodes_with_paths()
      |> Enum.map(fn {path, node} -> {path.segments, node.name} end)

    assert paths == [{["electrical", "legacy"], "legacy"}, {["gadget"], "gadget"}]
  end

  test "semantic entries expose object boundaries and computed paths" do
    {:ok, definition, [_unsupported_warning]} =
      Formentation.compile(
        %{
          kind: :object,
          properties: [
            {"title", %{kind: :string}},
            {"dimensions",
             %{
               kind: :object,
               properties: [
                 {"width", %{kind: :integer}},
                 {"depth", %{kind: :integer}},
                 {"height", %{kind: :integer}}
               ],
               groups: [%{id: "size", fields: ["height", "width"]}]
             }},
            {"legacy", %{kind: :file}}
          ],
          groups: [%{id: "main", fields: ["legacy", "title"]}]
        },
        adapter: Formentation.Definition.Source.Map
      )

    root = Semantic.root(definition)
    assert %Semantic.Entry{kind: :object, name: nil, instance_path: %{segments: []}} = root

    assert [
             %Semantic.Entry{kind: :field, name: "title", instance_path: %{segments: ["title"]}},
             %Semantic.Entry{
               kind: :object,
               name: "dimensions",
               instance_path: %{segments: ["dimensions"]}
             },
             %Semantic.Entry{
               kind: :unsupported,
               name: "legacy",
               instance_path: %{segments: ["legacy"]}
             }
           ] = Semantic.direct_children(root)

    dimensions = Semantic.find(definition, ["dimensions"])

    assert Enum.map(Semantic.direct_children(dimensions), fn entry ->
             {entry.kind, entry.name, entry.instance_path.segments, entry.template_path.segments}
           end) == [
             {:field, "width", ["dimensions", "width"], ["dimensions", "width"]},
             {:field, "depth", ["dimensions", "depth"], ["dimensions", "depth"]},
             {:field, "height", ["dimensions", "height"], ["dimensions", "height"]}
           ]

    assert Semantic.find(definition, ["main", "legacy"]) == nil
    assert Semantic.find(definition, ["dimensions", "size", "width"]) == nil
  end

  test "semantic queries read native-only definitions" do
    {:ok, definition} =
      Finalizer.finalize(
        Semantic.Object.new(nil, %TemplatePath{segments: []}, [
          Semantic.Field.new("name", %TemplatePath{segments: ["name"]}, :string,
            role: :text,
            required?: true,
            origins: [role: {:inference, :string_default}]
          )
        ]),
        Presentation.Object.new("/", [
          Presentation.Field.new("/name", label: "Name")
        ])
      )

    assert [%Semantic.Field{name: "name", required?: true}] = Info.fields(definition)
    assert %Semantic.Field{role: :text} = Info.node_at(definition, ["name"])
    assert Info.role(definition, ["name"]) == :text
    assert Info.required?(definition, ["name"])
  end

  test "presentation descriptors read native-only layout metadata" do
    {:ok, definition} =
      Finalizer.finalize(
        Semantic.Object.new(nil, %TemplatePath{segments: []}, [
          Semantic.Field.new("name", %TemplatePath{segments: ["name"]}, :string)
        ]),
        Presentation.Object.new("/", [
          Presentation.Group.new(
            "/#identity",
            [
              Presentation.Field.new("/name",
                label: "Display name",
                help: "Shown to technicians.",
                widget: :textarea,
                hidden?: true
              )
            ],
            label: "Identity"
          )
        ])
      )

    assert %Formentation.Info.Layout.Object{
             children: [
               %Formentation.Info.Layout.Group{
                 id: "/#identity",
                 label: "Identity",
                 children: [
                   %Formentation.Info.Layout.Field{
                     semantic_path: %{segments: ["name"]},
                     label: "Display name",
                     help: "Shown to technicians.",
                     widget: :textarea,
                     hidden?: true
                   }
                 ]
               }
             ]
           } = Info.presentation_root(definition)
  end
end
