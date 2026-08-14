defmodule Formentation.Fixtures.Addresses do
  @moduledoc """
  Differential fixture for an object-item collection (MB-S1, D-053/D-054):
  `addresses: collection<object{street: string, zip: string}>`. Proves the
  recursive item model — item-property requiredness and the item
  presentation subtree — not just the collection struct. The JSON Schema
  declaration lives beside this module as addresses/schema.json.
  """

  @behaviour Formentation.Fixture

  @fixture_dir Path.join(__DIR__, "addresses")

  @external_resource Path.join(@fixture_dir, "schema.json")
  @external_resource Path.join(@fixture_dir, "ui.json")

  # Decoded at compile time so an edit to the JSON reaches `mix test --stale`.
  @json_schema @fixture_dir |> Path.join("schema.json") |> File.read!() |> JSON.decode!()
  @ui_hints @fixture_dir |> Path.join("ui.json") |> File.read!() |> JSON.decode!()

  @impl true
  def map_source do
    %{
      kind: :object,
      title: "Address book",
      properties: [
        {"addresses",
         %{
           kind: :collection,
           title: "Addresses",
           item: %{
             kind: :object,
             title: "Address",
             required: ["street"],
             properties: [
               {"street", %{kind: :string, title: "Street", min_length: 1}},
               {"zip", %{kind: :string, title: "ZIP"}}
             ]
           }
         }}
      ]
    }
  end

  @impl true
  def json_schema, do: @json_schema

  @impl true
  def ui_hints, do: @ui_hints

  @impl true
  def field_names, do: ["street", "zip"]
end
