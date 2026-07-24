defmodule FormentationDemo.PumpInspectionBrowserTest do
  @moduledoc """
  Browser-real coverage for the pump-inspection demo. Each test pins a truth
  `Phoenix.LiveViewTest` cannot observe because it never runs the LiveSocket JS
  hook (see docs/superpowers/specs/2026-07-24-browser-testing-playwright-design.md).
  """
  use PhoenixTest.Playwright.Case, async: true

  # `browser: :chromium` (not the `:browser` shorthand): PhoenixTest.Playwright.Case's
  # setup_all reads the same `:browser` key from ExUnit tags to pick the browser engine
  # (defaulting to :chromium). `@moduletag :browser` sets `browser: true`, which crashes
  # NimbleOptions validation (`true` isn't one of :chromium/:firefox/...). Pinning it to
  # the (already-default) engine keeps the tag under the literal name `:browser` — so
  # `ExUnit.configure(exclude: [:browser])` / `--only browser` still select on presence
  # of that key — while giving the config consumer a value it accepts.
  @moduletag browser: :chromium

  test "a fully valid submit renders the decoded candidate", %{conn: conn} do
    # serial_number and condition are blank initially (required); the rest have
    # valid initial values (operating_hours 5102, voltage 230.0, insulation_ok true).
    conn
    |> visit("/")
    |> fill_in("Serial number", with: "PX-2044")
    |> select("Condition", option: "worn")
    |> click_button("Save")
    |> assert_has("pre#decoded-candidate", text: "PX-2044")
  end

  test "a pristine required field's error stays hidden until used or submitted", %{conn: conn} do
    conn
    |> visit("/")
    |> assert_has("form#asset-form")
    # pristine mount: the blank required serial_number shows no error
    |> refute_has("#asset_payload_serial_number_errors")
    # touch ONLY operating_hours; serial_number stays :unused via the LiveSocket _unused_
    # markers, so its error remains hidden. (Under LiveViewTest the whole form re-serializes
    # and this same assertion would FAIL — that is the divergence this test pins.)
    |> fill_in("Operating hours", with: "4800")
    |> assert_has("#asset_payload_operating_hours", value: "4800")
    |> refute_has("#asset_payload_serial_number_errors")
    # turn OFF native browser validation so the blank submit reaches the server; anchor on the
    # novalidate patch landing before clicking Save (else native validation blocks the submit)
    |> uncheck("Native browser validation")
    |> assert_has("form#asset-form[novalidate]")
    # submitting now gates every field's error open, including the untouched serial_number
    |> click_button("Save")
    |> assert_has("#asset_payload_serial_number_errors")
  end

  test "the number field keeps raw non-numeric text after the live round-trip (D-021)", %{
    conn: conn
  } do
    conn
    |> visit("/")
    # operating_hours renders type="text" inputmode="numeric", so the browser accepts "51o2"
    |> fill_in("Operating hours", with: "51o2")
    # the decode fails and its error appears (also anchors the assertion to the live patch)
    |> assert_has("#asset_payload_operating_hours_errors")
    # ...and the raw text survives the round-trip instead of being sanitized away
    |> assert_has("#asset_payload_operating_hours", value: "51o2")
  end

  test "clicking an error-summary link focuses the offending control", %{conn: conn} do
    conn
    |> visit("/")
    |> assert_has("form#asset-form")
    # turn OFF native validation so the blank submit reaches the server-side summary
    |> uncheck("Native browser validation")
    |> assert_has("form#asset-form[novalidate]")
    |> click_button("Save")
    |> assert_has(".ftn-error-summary[role='alert']")
    |> click_link(nil, "Serial number:", exact: false)
    |> assert_has("#asset_payload_serial_number:focus")
  end
end
