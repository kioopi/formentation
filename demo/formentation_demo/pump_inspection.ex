defmodule FormentationDemo.PumpInspection do
  @moduledoc """
  The end-to-end example's JSON Schema declaration and UI hints
  (docs/Formentation/Planning/17-end-to-end-example.md), owned by the
  demo because the demo compiles in dev where test fixtures do not.
  The test fixture `Formentation.Fixtures.PumpInspection` delegates
  `json_schema/0` and `ui_hints/0` here — one source of truth. The
  demo compiles through the JSON Schema adapter (not the map source)
  because only it carries an instance validator (D-012).
  """

  @schema_dir Path.join(__DIR__, "pump_inspection")

  @external_resource Path.join(@schema_dir, "schema.json")
  @external_resource Path.join(@schema_dir, "ui.json")

  # Decoded at compile time so an edit to the JSON reaches `mix test --stale`.
  @json_schema @schema_dir |> Path.join("schema.json") |> File.read!() |> JSON.decode!()
  @ui_hints @schema_dir |> Path.join("ui.json") |> File.read!() |> JSON.decode!()

  @doc "The decoded JSON Schema declaration (schema.json)."
  def json_schema, do: @json_schema

  @doc "The decoded UI-hints document (ui.json)."
  def ui_hints, do: @ui_hints

  @doc """
  The demo's initial data: a new-inspection posture — readings present,
  the required identity fields (serial number, condition) still blank,
  so error-visibility gating is demonstrable live.
  """
  def initial_data do
    %{"operating_hours" => 5102, "voltage" => 230.0, "insulation_ok" => true}
  end
end
