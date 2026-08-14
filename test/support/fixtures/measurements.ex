defmodule Formentation.Fixtures.Measurements do
  @moduledoc """
  Differential fixture for a scalar-item collection (MB-S1, D-053/D-054):
  `measurements: collection<number>, min 1, max 10`. The JSON Schema
  declaration lives beside this module as measurements/schema.json.
  """

  @behaviour Formentation.Fixture

  @fixture_dir Path.join(__DIR__, "measurements")

  @external_resource Path.join(@fixture_dir, "schema.json")
  @external_resource Path.join(@fixture_dir, "ui.json")

  # Decoded at compile time so an edit to the JSON reaches `mix test --stale`.
  @json_schema @fixture_dir |> Path.join("schema.json") |> File.read!() |> JSON.decode!()
  @ui_hints @fixture_dir |> Path.join("ui.json") |> File.read!() |> JSON.decode!()

  @impl true
  def map_source do
    %{
      kind: :object,
      title: "Measurement log",
      required: ["measurements"],
      properties: [
        {"measurements",
         %{
           kind: :collection,
           title: "Measurements",
           item: %{kind: :number},
           min_items: 1,
           max_items: 10
         }}
      ]
    }
  end

  @impl true
  def json_schema, do: @json_schema

  @impl true
  def ui_hints, do: @ui_hints

  @impl true
  def field_names, do: []
end
