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

  # LiveView attaches its client-side event handlers only once the LiveSocket
  # has joined, but `visit/2` returns on the page `load` event, which fires
  # earlier. Interacting inside that window produces no `phx-change` or
  # `phx-submit` push at all: the server never receives an event, so the DOM
  # never patches and no assertion timeout can rescue it — raising the 5s
  # timeout to 30s changes nothing, the run just waits 30s and still fails.
  #
  # `.phx-connected` is LiveView's own "this view has joined" marker, so
  # waiting on it closes the race. Note `assert_has("form#asset-form")` does
  # NOT: that element is present in the static render and matches before the
  # socket joins, which is why the tests below still flaked despite it.
  #
  # The join gets its own, longer timeout: it is the one step that legitimately
  # takes a while on a loaded machine (CI runners, a dev box mid-compile), and
  # unlike a post-interaction assertion it is genuinely waiting for something
  # that *will* arrive. Every later assertion keeps the default 5s, so a real
  # regression still fails fast rather than hanging.
  #
  # Measured on this suite, whole runs failed out of 8, with half the cores
  # busy-looping to stand in for a loaded CI runner: 4/8 before, 0/8 after.
  # Idle, 0/12 after. Under *full* CPU saturation the join itself starves and
  # runs still fail — that regime is not worth chasing, but it is why the
  # timeout above is generous rather than tight.
  @connect_timeout to_timeout(second: 15)

  defp visit_connected(conn, path) do
    conn |> visit(path) |> assert_has(".phx-connected", timeout: @connect_timeout)
  end

  test "a fully valid submit renders the decoded candidate", %{conn: conn} do
    # serial_number and condition are blank initially (required); the rest have
    # valid initial values (operating_hours 5102, voltage 230.0, insulation_ok true).
    conn
    |> visit_connected("/")
    |> fill_in("Serial number", with: "PX-2044")
    |> select("Condition", option: "worn")
    |> click_button("Save")
    |> assert_has("pre#decoded-candidate", text: "PX-2044")
  end

  test "a pristine required field's error stays hidden until used or submitted", %{conn: conn} do
    conn
    |> visit_connected("/")
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
    |> visit_connected("/")
    # operating_hours renders type="text" inputmode="numeric", so the browser accepts "51o2"
    |> fill_in("Operating hours", with: "51o2")
    # the decode fails and its error appears (also anchors the assertion to the live patch)
    |> assert_has("#asset_payload_operating_hours_errors")
    # ...and the raw text survives the round-trip instead of being sanitized away
    |> assert_has("#asset_payload_operating_hours", value: "51o2")
  end

  test "clicking an error-summary link focuses the offending control", %{conn: conn} do
    conn
    |> visit_connected("/")
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
