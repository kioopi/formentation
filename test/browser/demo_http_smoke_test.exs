defmodule FormentationDemo.DemoHttpSmokeTest do
  @moduledoc """
  A real over-the-wire smoke test of the running demo server. Unlike the
  Playwright cases it runs no browser JS: it does a plain HTTP GET against the
  endpoint `test/test_helper.exs` boots with `server: true` on port 4002 in the
  E2E lane, and asserts the server-rendered ("dead render") HTML. Proves the
  demo actually serves both of its pages over a socket.
  """
  use ExUnit.Case, async: true

  # Runs only in the E2E lane (`mix test.browser`), where the harness starts a
  # listening server. `browser: :chromium` (not the `:browser` shorthand)
  # matches the tag that lane selects on; see FormentationDemo.PumpInspectionBrowserTest
  # for why the value is pinned to an engine name.
  @moduletag browser: :chromium

  setup_all do
    {:ok, _} = Application.ensure_all_started(:inets)
    :ok
  end

  defp get(path) do
    url = String.to_charlist(FormentationDemo.Endpoint.url() <> path)

    {:ok, {{_http, status, _reason}, _headers, body}} =
      :httpc.request(:get, {url, []}, [], body_format: :binary)

    {status, body}
  end

  test "GET / serves the pump-inspection form with its initial data" do
    {status, body} = get("/")

    assert status == 200
    assert body =~ ~s(id="asset-form")
    # operating_hours' initial value from the demo schema, rendered server-side
    assert body =~ "5102"
  end

  test "GET /nested serves the nested-object demo form" do
    {status, body} = get("/nested")

    assert status == 200
    assert body =~ ~s(id="nested-form")
  end
end
