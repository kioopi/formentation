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

  @external_resource Path.join(@fixture_dir, "schema.json")
  @external_resource Path.join(@fixture_dir, "ui.json")

  # Decoded at compile time so an edit to the JSON reaches `mix test --stale`.
  @json_schema @fixture_dir |> Path.join("schema.json") |> File.read!() |> JSON.decode!()
  @ui_hints @fixture_dir |> Path.join("ui.json") |> File.read!() |> JSON.decode!()

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
  def json_schema, do: @json_schema

  @impl true
  def ui_hints, do: @ui_hints

  @impl true
  def field_names, do: ["legacy_id", "location", "serial_number"]
end
