defmodule Formentation.InfoTest do
  use ExUnit.Case, async: true

  alias Formentation.{Definition, Info, Node, Presentation, Semantic, TemplatePath}
  alias Formentation.Definition.Finalizer

  doctest Formentation.Info

  # A hand-built per-kind tree: proves Info reads the split structs
  # without going through a source adapter. Shape: a root group with a
  # required field, a data-nesting group wrapping a presentational
  # fieldset around one field, and an unsupported node.
  defp definition do
    name = %Node.Field{
      id: "/name",
      name: "name",
      label: "Name",
      value_type: :string,
      role: :text,
      required?: true,
      template_path: %TemplatePath{segments: ["name"]},
      origins: [label: {:inference, :humanize}]
    }

    voltage = %Node.Field{
      id: "/electrical/voltage",
      name: "voltage",
      value_type: :integer,
      role: :integer,
      group: "power",
      template_path: %TemplatePath{segments: ["electrical", "voltage"]}
    }

    legacy = %Node.Unsupported{
      id: "/electrical/legacy",
      name: "legacy",
      required?: true,
      template_path: %TemplatePath{segments: ["electrical", "legacy"]}
    }

    fieldset = %Node.Group{
      id: "/electrical#power",
      nests_data?: false,
      label: "Power",
      template_path: %TemplatePath{segments: ["electrical"]},
      children: [voltage, legacy]
    }

    electrical = %Node.Group{
      id: "/electrical",
      name: "electrical",
      nests_data?: true,
      template_path: %TemplatePath{segments: ["electrical"]},
      children: [fieldset]
    }

    gadget = %Node.Unsupported{
      id: "/gadget",
      name: "gadget",
      template_path: %TemplatePath{segments: ["gadget"]}
    }

    root = %Node.Group{
      id: "/",
      nests_data?: true,
      template_path: %TemplatePath{segments: []},
      children: [name, electrical, gadget]
    }

    %Definition{root: root}
  end

  test "fields/1 returns exactly the field nodes, in tree order" do
    assert ["name", "voltage"] == definition() |> Info.fields() |> Enum.map(& &1.name)
  end

  test "node_at/2 descends data groups and looks through presentational groups" do
    assert %Node.Field{id: "/electrical/voltage"} =
             Info.node_at(definition(), ["electrical", "voltage"])
  end

  test "node_at/2 finds unsupported nodes" do
    assert %Node.Unsupported{id: "/gadget"} = Info.node_at(definition(), ["gadget"])
  end

  test "node/2 finds any node by id, including presentational groups" do
    assert %Node.Group{nests_data?: false} = Info.node(definition(), "/electrical#power")
  end

  test "role/2, origins/2, and required?/2 read per-kind nodes" do
    assert Info.role(definition(), ["name"]) == :text
    assert Info.origins(definition(), ["name"]) == [label: {:inference, :humanize}]
    assert Info.required?(definition(), ["name"])
    refute Info.required?(definition(), ["electrical", "voltage"])
  end

  test "role/2 is nil for groups and missing paths, origins/2 empty for missing paths" do
    assert Info.role(definition(), ["electrical"]) == nil
    assert Info.role(definition(), ["missing"]) == nil
    assert Info.origins(definition(), ["missing"]) == []
  end

  test "semantic_kind/2 classifies paths without accepting presentation group IDs" do
    assert Info.semantic_kind(definition(), []) == :object
    assert Info.semantic_kind(definition(), ["name"]) == :field
    assert Info.semantic_kind(definition(), ["electrical"]) == :object
    assert Info.semantic_kind(definition(), ["electrical", "legacy"]) == :unsupported
    assert Info.semantic_kind(definition(), ["electrical", "power"]) == nil
    assert Info.semantic_kind(definition(), ["missing"]) == nil
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
    assert %Node.Unsupported{id: "/electrical/legacy", required?: true} = legacy
  end

  test "unsupported_nodes/1 is empty when there are none" do
    root = %Node.Group{
      id: "/",
      nests_data?: true,
      template_path: %TemplatePath{segments: []},
      children: []
    }

    assert Info.unsupported_nodes(%Definition{root: root}) == []
  end

  test "unsupported_nodes_with_paths/1 pairs nodes with instance paths through both group flavors" do
    paths =
      definition()
      |> Info.unsupported_nodes_with_paths()
      |> Enum.map(fn {path, node} -> {path.segments, node.name} end)

    # legacy lives inside data-nesting `electrical` and presentation `fieldset`:
    # the data group contributes "electrical", the presentation group nothing.
    assert paths == [{["electrical", "legacy"], "legacy"}, {["gadget"], "gadget"}]
  end

  test "semantic fallback order preserves unstamped mixed-tree order" do
    a = %Node.Field{
      id: "/a",
      name: "a",
      value_type: :string,
      template_path: %TemplatePath{segments: ["a"]}
    }

    legacy = %Node.Unsupported{
      id: "/legacy",
      name: "legacy",
      template_path: %TemplatePath{segments: ["legacy"]}
    }

    group = %Node.Group{
      id: "/#grouped",
      nests_data?: false,
      template_path: %TemplatePath{segments: []},
      children: [a, legacy]
    }

    b = %Node.Field{
      id: "/b",
      name: "b",
      value_type: :string,
      template_path: %TemplatePath{segments: ["b"]}
    }

    gadget = %Node.Unsupported{
      id: "/gadget",
      name: "gadget",
      template_path: %TemplatePath{segments: ["gadget"]}
    }

    root = %Node.Group{
      id: "/",
      nests_data?: true,
      template_path: %TemplatePath{segments: []},
      children: [group, b, gadget]
    }

    definition = %Definition{root: root}

    assert ["a", "b"] == definition |> Info.fields() |> Enum.map(& &1.name)
    assert ["legacy", "gadget"] == definition |> Info.unsupported_nodes() |> Enum.map(& &1.name)
  end

  test "semantic_kind/2 raises on ambiguous hand-built paths without changing node_at/2" do
    first = %Node.Group{
      id: "/a",
      name: "a",
      nests_data?: true,
      template_path: %TemplatePath{segments: ["a"]},
      children: [
        %Node.Field{
          id: "/a/x",
          name: "x",
          value_type: :string,
          template_path: %TemplatePath{segments: ["a", "x"]}
        }
      ]
    }

    second = %Node.Group{
      id: "/a",
      name: "a",
      nests_data?: true,
      template_path: %TemplatePath{segments: ["a"]},
      children: [
        %Node.Field{
          id: "/a/y",
          name: "y",
          value_type: :string,
          template_path: %TemplatePath{segments: ["a", "y"]}
        }
      ]
    }

    root = %Node.Group{
      id: "/",
      nests_data?: true,
      template_path: %TemplatePath{segments: []},
      children: [first, second]
    }

    definition = %Definition{root: root}

    assert Info.node_at(definition, ["a", "y"]) == nil

    assert_raise ArgumentError, ~r/ambiguous semantic path \["a", "y"\]/, fn ->
      Info.semantic_kind(definition, ["a", "y"])
    end
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
        adapter: Formentation.Source.Map
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

    assert definition.root == nil
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
            "identity",
            [
              Presentation.Field.new("/name",
                label: "Display name",
                help: "Shown to technicians.",
                widget: :textarea,
                hidden?: true
              )
            ],
            layout_id: "/#identity",
            label: "Identity"
          )
        ])
      )

    assert %Formentation.Info.Presentation.Object{
             children: [
               %Formentation.Info.Presentation.Group{
                 id: "/#identity",
                 label: "Identity",
                 children: [
                   %Formentation.Info.Presentation.Field{
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
