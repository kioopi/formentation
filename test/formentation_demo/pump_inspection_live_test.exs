defmodule FormentationDemo.PumpInspectionLiveTest do
  use ExUnit.Case, async: true

  import Formentation.HTMLAssertions
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint FormentationDemo.Endpoint

  @valid_payload %{
    "serial_number" => "PX-2044",
    "condition" => "worn",
    "last_service" => "2026-06-30",
    "operating_hours" => "4800",
    "voltage" => "230.0",
    "insulation_ok" => "true",
    "notes" => "Runs fine."
  }

  defp mount! do
    {:ok, lv, html} = live(build_conn(), "/")
    {lv, html}
  end

  describe "initial render" do
    test "shows initial data under the parent namespace with unique ids" do
      {_lv, html} = mount!()
      doc = parse!(html)

      assert_no_duplicate_ids(doc)

      assert [hours] = Floki.find(doc, "input[name='asset[payload][operating_hours]']")
      assert Floki.attribute(hours, "value") == ["5102"]

      assert [_name] = Floki.find(doc, "input[name='asset[name]']")
      assert [_form] = Floki.find(doc, "form#asset-form")
      assert Floki.find(doc, "form form") == []
    end

    test "stores but hides the blank-required issues of a pristine form" do
      {_lv, html} = mount!()
      doc = parse!(html)

      assert [serial] = Floki.find(doc, "input[name='asset[payload][serial_number]']")
      assert Floki.attribute(serial, "value") in [[], [""]]
      assert Floki.find(doc, "ul.ftn-errors") == []
      assert Floki.find(doc, ".ftn-error-summary") == []
    end
  end

  describe "phx-change" do
    # Known uncertainty 1, RECONCILED: the brief assumed Phoenix.LiveViewTest's
    # `form/3` + `render_change/1` would carry an `_unused_serial_number` marker
    # for a field the call didn't mention, keeping it "untouched" and its issue
    # hidden. Reality (confirmed via a temporary `IO.inspect(asset_params, ...)`
    # in the handler, since removed): `form/3` re-serializes the ENTIRE rendered
    # <form> on every call, merging the override map on top of every input's
    # current DOM value — so `serial_number` arrives as an ordinary provided key,
    # `"serial_number" => ""`, with no `_unused_` marker at all:
    #
    #     params: %{"name" => "Pump 7", "payload" => %{"condition" => "",
    #       "insulation_ok" => "true", "last_service" => "", "notes" => "",
    #       "operating_hours" => "4800", "serial_number" => "", "voltage" => "230.0"}}
    #
    # `Formentation.Transport.normalize/1` only marks a path `:unused` when it
    # finds a sibling `_unused_<key>`; Formentation itself renders no such hidden
    # markers (that convention belongs to Phoenix's own checkbox/select helpers,
    # not to plain text inputs). So every key present in a full-form change is
    # `:used`, whether or not the browser truly needed to resend it, and the
    # required-but-blank serial_number's issue is visible from the very first
    # `render_change`, not just after the field named it directly.
    test "a full-form phx-change surfaces every field's real value, not just the changed one" do
      {lv, _html} = mount!()

      html =
        lv
        |> form("#asset-form", %{"asset" => %{"payload" => %{"operating_hours" => "4800"}}})
        |> render_change()

      doc = parse!(html)
      # serial_number was resent blank by the full-form serialization: visible immediately
      assert [_errors] = Floki.find(doc, "#asset_payload_serial_number_errors")
      assert [serial] = Floki.find(doc, "input[name='asset[payload][serial_number]']")
      assert Floki.attribute(serial, "aria-invalid") == ["true"]

      html =
        lv
        |> form("#asset-form", %{"asset" => %{"payload" => %{"serial_number" => "PX"}}})
        |> render_change()

      doc = parse!(html)
      # still too short (minLength 4): stays visible, control marked invalid
      assert [_errors] = Floki.find(doc, "#asset_payload_serial_number_errors")
      assert [serial] = Floki.find(doc, "input[name='asset[payload][serial_number]']")
      assert Floki.attribute(serial, "aria-invalid") == ["true"]
    end

    test "failed decode preserves the typed text on screen" do
      {lv, _html} = mount!()

      html =
        lv
        |> form("#asset-form", %{"asset" => %{"payload" => %{"operating_hours" => "51o2"}}})
        |> render_change()

      doc = parse!(html)
      assert [hours] = Floki.find(doc, "input[name='asset[payload][operating_hours]']")
      assert Floki.attribute(hours, "value") == ["51o2"]
      assert [_errors] = Floki.find(doc, "#asset_payload_operating_hours_errors")
      refute html =~ "decoded-candidate"
    end
  end

  describe "phx-submit" do
    test "failed submit shows every error and a summary with working links" do
      {lv, _html} = mount!()

      html =
        lv
        |> form("#asset-form", %{"asset" => %{"payload" => %{}}})
        |> render_submit()

      doc = parse!(html)
      assert [summary] = Floki.find(doc, ".ftn-error-summary")
      assert Floki.attribute(summary, "role") == ["alert"]

      # each summary entry links to an existing control id
      for href <- Floki.attribute(Floki.find(summary, "a"), "href") do
        "#" <> id = href
        assert [_control] = Floki.find(doc, "##{id}")
      end

      # the untouched blank serial number is now visible (submit gate)
      assert [_errors] = Floki.find(doc, "#asset_payload_serial_number_errors")
      refute html =~ "decoded-candidate"
    end

    test "valid submit renders the decoded candidate as the documented JSON" do
      {lv, _html} = mount!()

      html =
        lv
        |> form("#asset-form", %{"asset" => %{"payload" => @valid_payload}})
        |> render_submit()

      doc = parse!(html)
      assert [pre] = Floki.find(doc, "pre#decoded-candidate")

      assert JSON.decode!(Floki.text(pre)) == %{
               "serial_number" => "PX-2044",
               "condition" => "worn",
               "last_service" => "2026-06-30",
               "operating_hours" => 4800,
               "voltage" => 230.0,
               "insulation_ok" => true,
               "notes" => "Runs fine."
             }
    end

    test "after a failed submit, edits keep field errors visible and drop the summary" do
      {lv, _html} = mount!()

      lv
      |> form("#asset-form", %{"asset" => %{"payload" => %{}}})
      |> render_submit()

      html =
        lv
        |> form("#asset-form", %{"asset" => %{"payload" => %{"voltage" => "231"}}})
        |> render_change()

      doc = parse!(html)
      # Every field is :used after ANY full-form event in Phoenix.LiveViewTest,
      # submit included — the describe "phx-change" comment above establishes
      # that `form/3` + `render_change/1` re-serialize the entire rendered
      # form with no `_unused_` markers at all; that holds for `render_submit/1`
      # too, so the prior submit already marked every path :used. Errors
      # therefore survive this post-submit :change regardless of which field
      # it names:
      assert [_errors] = Floki.find(doc, "#asset_payload_serial_number_errors")
      # ...while the submit-gated summary hides again
      assert Floki.find(doc, ".ftn-error-summary") == []
    end
  end

  describe "_persistent_id arrival" do
    test "a _persistent_id in the payload is transport metadata: decoded submission omits it" do
      {lv, _html} = mount!()

      payload = Map.put(@valid_payload, "_persistent_id", "0")
      html = render_submit(lv, "save", %{"asset" => %{"payload" => payload}})

      doc = parse!(html)
      assert [pre] = Floki.find(doc, "pre#decoded-candidate")

      decoded = JSON.decode!(Floki.text(pre))
      refute Map.has_key?(decoded, "_persistent_id")
      assert decoded["serial_number"] == "PX-2044"
    end
  end

  describe "native-validation toggle" do
    # Deviation from the brief: HEEx renders a true boolean global as
    # `attr=""` (empty value), not `attr="attr"` — the same convention this
    # very form already uses for `required=""` and `checked=""`. Floki
    # therefore reports the attribute's value as `[""]`, not `["novalidate"]`,
    # when present. Confirmed by dumping the raw rendered `<form>` tag.
    test "toggles the novalidate attribute on the form" do
      {:ok, lv, html} = live(build_conn(), "/")

      # default: native validation ON -> form carries no novalidate attribute
      assert [form] = Floki.find(parse!(html), "form#asset-form")
      assert Floki.attribute(form, "novalidate") == []

      # turn native validation OFF -> novalidate present
      html = lv |> element("#toggle-native-validation") |> render_click()
      assert [form] = Floki.find(parse!(html), "form#asset-form")
      assert Floki.attribute(form, "novalidate") == [""]

      # toggle back ON -> novalidate gone again
      html = lv |> element("#toggle-native-validation") |> render_click()
      assert [form] = Floki.find(parse!(html), "form#asset-form")
      assert Floki.attribute(form, "novalidate") == []
    end
  end

  describe "auto-recovery" do
    test "replaying the last change on a fresh mount reproduces the state" do
      change = %{"asset" => %{"payload" => %{"operating_hours" => "51o2"}}}

      {lv1, _html} = mount!()
      html1 = render_change(lv1, "validate", change)

      {lv2, _html} = mount!()
      html2 = render_change(lv2, "validate", change)

      extract = fn html ->
        doc = parse!(html)
        [hours] = Floki.find(doc, "input[name='asset[payload][operating_hours]']")

        {Floki.attribute(hours, "value"),
         Floki.find(doc, "#asset_payload_operating_hours_errors") != []}
      end

      assert extract.(html1) == {["51o2"], true}
      assert extract.(html2) == extract.(html1)
    end
  end
end
