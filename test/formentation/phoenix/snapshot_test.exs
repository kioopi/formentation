defmodule Formentation.Phoenix.SnapshotTest do
  use ExUnit.Case, async: true

  import Formentation.HTMLAssertions
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Formentation.Fixtures.PumpInspection
  alias Formentation.Form
  alias Phoenix.HTML.FormData

  @snapshot Path.expand("../../support/fixtures/pump_inspection/static_render.html", __DIR__)

  # The phase's "one reviewed snapshot per example form": the end-to-end
  # example rendered statically under the parent namespace. To update
  # intentionally: delete the file, rerun, review the diff, commit.
  # The compare is byte-exact: editor auto-formatting of the .html fixture
  # (e.g. "insert final newline") breaks the test just as surely as a real
  # markup change, so save it as generated, not through a formatter.
  test "the end-to-end example renders as reviewed" do
    {:ok, definition, _diagnostics} =
      Formentation.compile(PumpInspection.map_source(), adapter: Formentation.Source.Map)

    data = %{
      "serial_number" => "PX-2044",
      "condition" => "worn",
      "last_service" => "2026-06-30",
      "operating_hours" => 5102,
      "voltage" => 230.0,
      "insulation_ok" => true,
      "notes" => "Runs fine."
    }

    form =
      FormData.to_form(Form.new(definition, data), as: "asset[payload]", id: "asset_payload")

    html =
      render_component(&Formentation.Phoenix.fields/1, definition: definition, form: form)

    doc = parse!(html)
    assert_no_duplicate_ids(doc)
    assert_labelled(doc, "asset_payload_serial_number")
    assert_labelled(doc, "asset_payload_notes")
    assert describedby(doc, "asset_payload_notes") == ["asset_payload_notes_help"]
    assert Floki.text(find_one(doc, "fieldset.ftn-group legend")) == "Electrical"
    assert Floki.find(doc, "form") == []

    if File.exists?(@snapshot) do
      assert html == File.read!(@snapshot)
    else
      File.write!(@snapshot, html)
      flunk("Snapshot written to #{@snapshot} — review the HTML, then rerun.")
    end
  end
end
