browser? = !!System.get_env("PLAYWRIGHT_E2E")
browser_port = System.get_env("FORMENTATION_BROWSER_PORT", "4002") |> String.to_integer()

endpoint_base = [
  secret_key_base: String.duplicate("formentation-demo-", 4),
  live_view: [signing_salt: "ftn-demo-lv"],
  pubsub_server: FormentationDemo.PubSub
]

endpoint_server =
  if browser? do
    [
      adapter: Bandit.PhoenixAdapter,
      server: true,
      http: [ip: {127, 0, 0, 1}, port: browser_port],
      url: [host: "localhost", port: browser_port]
    ]
  else
    [server: false]
  end

Application.put_env(:formentation, FormentationDemo.Endpoint, endpoint_base ++ endpoint_server)

{:ok, _supervisor} =
  Supervisor.start_link(
    [
      {Phoenix.PubSub, name: FormentationDemo.PubSub},
      FormentationDemo.Endpoint
    ],
    strategy: :one_for_one,
    name: FormentationDemo.Supervisor
  )

if browser? do
  install_root =
    case System.cmd("mise", ["where", "npm:playwright"], stderr_to_stdout: true) do
      {path, 0} ->
        String.trim(path)

      {out, _} ->
        raise "Playwright not found (`mise where npm:playwright` failed): #{out}. " <>
                "Run `mise install` and `mise run playwright-browsers`."
    end

  # mise's npm backend lays npm:playwright under different subpaths across
  # versions (`<root>/lib/node_modules/...` on mise 2026.7.5, `<root>/node_modules/...`
  # on 2026.7.12+), so locate playwright's cli.js wherever it actually landed
  # instead of assuming a fixed subdir. PHX_TEST_PLAYWRIGHT_ASSETS_DIR overrides.
  cli_candidates =
    [
      Path.join([install_root, "lib", "node_modules", "playwright", "cli.js"]),
      Path.join([install_root, "node_modules", "playwright", "cli.js"])
    ] ++ Path.wildcard(Path.join(install_root, "**/node_modules/playwright/cli.js"))

  assets_dir =
    System.get_env("PHX_TEST_PLAYWRIGHT_ASSETS_DIR") ||
      case Enum.find(cli_candidates, &File.exists?/1) do
        nil ->
          raise "Playwright package (node_modules/playwright/cli.js) not found under " <>
                  "#{install_root} (searched: #{Enum.join(cli_candidates, ", ")}). " <>
                  "Set PHX_TEST_PLAYWRIGHT_ASSETS_DIR or re-run `mise install`."

        cli ->
          # assets_dir is the directory that contains node_modules/
          cli |> Path.dirname() |> Path.dirname() |> Path.dirname()
      end

  Application.put_env(:phoenix_test, :otp_app, :formentation)

  Application.put_env(:phoenix_test, :playwright,
    assets_dir: assets_dir,
    headless: true,
    timeout: to_timeout(second: 5)
  )

  Application.put_env(:phoenix_test, :base_url, FormentationDemo.Endpoint.url())

  {:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
end

ExUnit.configure(exclude: [:browser])
ExUnit.start(capture_log: true)
