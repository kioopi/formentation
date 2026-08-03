defmodule Formentation.Phoenix.SnapshotTest do
  use ExUnit.Case, async: true

  import Formentation.HTMLAssertions
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Formentation.{Fixtures.PumpInspection, Form, InstancePath}
  alias Formentation.Phoenix.DOMIdentity
  alias Phoenix.HTML.FormData

  @snapshot Path.expand("../../support/fixtures/pump_inspection/static_render.html", __DIR__)

  # The phase's "one reviewed snapshot per example form": the end-to-end
  # example rendered statically under the parent namespace. To update
  # intentionally: delete the file, rerun, review the diff, commit.
  # The compare is byte-exact apart from a conventional terminal newline in
  # the checked-in text fixture. All rendered markup remains significant.
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
    serial_id = DOMIdentity.field("asset_payload", InstancePath.new!(["serial_number"]), :control)
    notes_id = DOMIdentity.field("asset_payload", InstancePath.new!(["notes"]), :control)
    notes_help_id = DOMIdentity.field("asset_payload", InstancePath.new!(["notes"]), :help)

    assert_labelled(doc, serial_id)
    assert_labelled(doc, notes_id)
    assert describedby(doc, notes_id) == [notes_help_id]
    assert Floki.text(find_one(doc, "fieldset.ftn-group legend")) == "Electrical"
    assert Floki.find(doc, "form") == []

    if File.exists?(@snapshot) do
      assert html == String.trim_trailing(File.read!(@snapshot), "\n")
    else
      File.write!(@snapshot, html)
      flunk("Snapshot written to #{@snapshot} — review the HTML, then rerun.")
    end
  end
end
