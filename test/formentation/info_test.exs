defmodule Formentation.InfoTest do
  use ExUnit.Case, async: true

  alias Formentation.{Definition, Info, Node, TemplatePath}

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
end
