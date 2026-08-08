defmodule Formentation.PumpInspectionTest do
  use ExUnit.Case, async: true

  alias Formentation.Definition.{Presentation, Semantic}
  alias Formentation.Fixtures.PumpInspection
  alias Formentation.Info
  alias Formentation.Info.Layout, as: PresentationInfo

  setup do
    {:ok, definition, []} =
      Formentation.compile(PumpInspection.map_source(),
        adapter: Formentation.Source.Map
      )

    %{definition: definition}
  end

  test "compiles every field of the end-to-end example in order", %{definition: definition} do
    assert Enum.map(Info.fields(definition), & &1.name) == PumpInspection.field_names()
  end

  test "answers the Info queries from the end-to-end example", %{definition: definition} do
    assert Info.required?(definition, ["serial_number"]) == true
    assert Info.required?(definition, ["voltage"]) == false
    assert Info.role(definition, ["last_service"]) == :date
    assert Info.role(definition, ["condition"]) == :select

    assert {:ok, %PresentationInfo.Field{semantic_path: %{segments: ["voltage"]}}} =
             Info.presentation_at(definition, ["voltage"])

    assert %Semantic.Field{options: ["good", "worn", "defective"]} =
             Info.node_at(definition, ["condition"])
  end

  test "notes carries its overrides with origins", %{definition: definition} do
    assert {:ok, %PresentationInfo.Field{widget: :textarea, help: "Visible to all technicians."}} =
             Info.presentation_at(definition, ["notes"])

    origins = Info.origins(definition, ["notes"])
    assert origins[:label] == {:map_source, [:properties, "notes", :title]}
    assert origins[:role] == {:inference, :string_default}
    assert origins[:widget] == {:map_source, [:properties, "notes", :widget]}
    assert origins[:help] == {:map_source, [:properties, "notes", :help]}
  end

  test "constraints useful for presentation are preserved", %{definition: definition} do
    assert Info.node_at(definition, ["serial_number"]).constraints == %{min_length: 4}
    assert Info.node_at(definition, ["operating_hours"]).constraints == %{min: 0}
  end

  test "the electrical group renders as presentation only", %{definition: definition} do
    group = Info.node(definition, "/#electrical")
    assert %Presentation.Group{label: "Electrical"} = group
    assert Enum.map(group.children, & &1.semantic_id) == ["/voltage", "/insulation_ok"]
  end

  test "compilation is deterministic", %{definition: definition} do
    {:ok, again, []} =
      Formentation.compile(PumpInspection.map_source(),
        adapter: Formentation.Source.Map
      )

    assert again == definition
  end

  describe "JSON declarations of the same form" do
    test "the schema fixture decodes with exactly the known field names" do
      schema = PumpInspection.json_schema()

      assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
      assert schema["type"] == "object"
      assert Enum.sort(Map.keys(schema["properties"])) == Enum.sort(PumpInspection.field_names())
      assert schema["required"] == ["serial_number", "condition", "mounting"]
    end

    test "the ui fixture references only known field names" do
      ui = PumpInspection.ui_hints()
      known = PumpInspection.field_names()

      group_fields = Enum.flat_map(ui["groups"], & &1["fields"])
      assert Enum.all?(group_fields, &(&1 in known))
      assert Enum.all?(Map.keys(ui["fields"]), &(&1 in known))

      group_ids = Enum.map(ui["groups"], & &1["id"])
      assert Enum.all?(ui["order"], &(&1 in known or &1 in group_ids))
    end
  end
end
