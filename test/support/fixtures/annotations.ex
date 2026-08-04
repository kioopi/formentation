defmodule Formentation.Fixtures.Annotations do
  @moduledoc """
  Differential fixture for the annotations mini-slice keywords — const,
  description, examples, default — including the help hint overriding a
  schema description
  (docs/superpowers/specs/2026-07-21-phase1-annotations-mini-slice-design.md).
  The JSON Schema declaration and UI hints live beside this module as
  annotations/schema.json and annotations/ui.json.
  """

  @behaviour Formentation.Fixture

  @fixture_dir Path.join(__DIR__, "annotations")

  @external_resource Path.join(@fixture_dir, "schema.json")
  @external_resource Path.join(@fixture_dir, "ui.json")

  # Decoded at compile time, not per call: @external_resource forces the
  # recompile when the JSON changes, but only a change in the module's
  # compiled content propagates staleness to the tests that use it.
  @json_schema @fixture_dir |> Path.join("schema.json") |> File.read!() |> JSON.decode!()
  @ui_hints @fixture_dir |> Path.join("ui.json") |> File.read!() |> JSON.decode!()

  @impl true
  def map_source do
    %{
      kind: :object,
      title: "Inspection protocol",
      help: "Recorded at the end of each shift.",
      properties: [
        {"checklist_version", %{kind: :string, one_of: ["2"]}},
        {"reviewed_by",
         %{
           kind: :string,
           help: "Full name of the reviewing engineer.",
           examples: ["J. Doe"],
           default: "unassigned"
         }},
        {"summary", %{kind: :string, help: "Keep it under two sentences."}}
      ]
    }
  end

  @impl true
  def json_schema, do: @json_schema

  @impl true
  def ui_hints, do: @ui_hints

  @impl true
  def field_names, do: ["checklist_version", "reviewed_by", "summary"]
end
