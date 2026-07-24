browser? = !!System.get_env("PLAYWRIGHT_E2E")

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
      http: [ip: {127, 0, 0, 1}, port: 4002],
      url: [host: "localhost", port: 4002]
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
  assets_dir =
    System.get_env("PHX_TEST_PLAYWRIGHT_ASSETS_DIR") ||
      case System.cmd("mise", ["where", "npm:playwright"], stderr_to_stdout: true) do
        {path, 0} ->
          Path.join(String.trim(path), "lib")

        {out, _} ->
          raise "Playwright not found (`mise where npm:playwright` failed): #{out}. " <>
                  "Run `mise install` and `mise run playwright-browsers`."
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
