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

    fieldset = %Node.Group{
      id: "/electrical#power",
      nests_data?: false,
      label: "Power",
      template_path: %TemplatePath{segments: ["electrical"]},
      children: [voltage]
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
end
