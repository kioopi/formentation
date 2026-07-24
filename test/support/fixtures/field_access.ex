defmodule Formentation.Fixtures.FieldAccess do
  @moduledoc """
  Differential fixture for the non-submitting-fields mini-slice hints —
  hidden and read_only
  (docs/superpowers/specs/2026-07-22-phase1-non-submitting-fields-design.md).
  The JSON Schema declaration and UI hints live beside this module as
  field_access/schema.json and field_access/ui.json.
  """

  @behaviour Formentation.Fixture

  @fixture_dir Path.join(__DIR__, "field_access")

  @impl true
  def map_source do
    %{
      kind: :object,
      title: "Device registration",
      properties: [
        {"legacy_id", %{kind: :string, hidden: true}},
        {"location", %{kind: :string}},
        {"serial_number", %{kind: :string, read_only: true}}
      ]
    }
  end

  @impl true
  def json_schema, do: decode!("schema.json")

  @impl true
  def ui_hints, do: decode!("ui.json")

  @impl true
  def field_names, do: ["legacy_id", "location", "serial_number"]

  defp decode!(name) do
    @fixture_dir |> Path.join(name) |> File.read!() |> JSON.decode!()
  end
end
