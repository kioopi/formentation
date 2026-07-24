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
  def json_schema, do: decode!("schema.json")

  @impl true
  def ui_hints, do: decode!("ui.json")

  @impl true
  def field_names, do: ["checklist_version", "reviewed_by", "summary"]

  defp decode!(name) do
    @fixture_dir |> Path.join(name) |> File.read!() |> JSON.decode!()
  end
end
