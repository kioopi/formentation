defmodule Formentation.Fixtures.PumpInspection do
  @moduledoc """
  The end-to-end example (docs/Formentation/Planning/17-end-to-end-example.md) as a
  map-source fixture with expected Info answers. The JSON Schema declaration
  and UI hints are owned by `FormentationDemo.PumpInspection` (dev-compilable
  for the demo) and delegated to here.
  """

  @behaviour Formentation.Fixture

  @impl true
  def map_source do
    %{
      kind: :object,
      title: "Pump inspection",
      required: ["serial_number", "condition", "mounting"],
      properties: [
        {"serial_number", %{kind: :string, title: "Serial number", min_length: 4}},
        {"condition",
         %{
           kind: :string,
           title: "Condition",
           one_of: ["good", "worn", "defective"]
         }},
        {"mounting",
         %{
           kind: :string,
           title: "Mounting",
           one_of: ["floor", "wall"],
           widget: :radio
         }},
        {"last_service", %{kind: :string, title: "Last service", role: :date}},
        {"operating_hours", %{kind: :integer, title: "Operating hours", min: 0}},
        {"voltage", %{kind: :number, title: "Voltage (V)"}},
        {"insulation_ok", %{kind: :boolean, title: "Insulation test passed"}},
        {"notes",
         %{
           kind: :string,
           title: "Notes",
           widget: :textarea,
           help: "Visible to all technicians."
         }}
      ],
      groups: [%{id: "electrical", title: "Electrical", fields: ["voltage", "insulation_ok"]}]
    }
  end

  @impl true
  defdelegate json_schema, to: FormentationDemo.PumpInspection

  @impl true
  defdelegate ui_hints, to: FormentationDemo.PumpInspection

  @impl true
  def field_names do
    [
      "serial_number",
      "condition",
      "mounting",
      "last_service",
      "operating_hours",
      "voltage",
      "insulation_ok",
      "notes"
    ]
  end
end
