defmodule Mix.Tasks.Demo do
  @shortdoc "Serves the Formentation demo (default http://localhost:4000)"

  @moduledoc """
  Boots FormentationDemo.Endpoint on Bandit (dev only). The pump
  inspection example lives at `/`, the nested-object example at
  `/nested`. Stop with Ctrl-C.

  ## Usage

      mix demo [port]

  Defaults to port 4000 when no argument is given.
  """

  use Mix.Task

  @impl true
  def run(args) do
    port =
      case args do
        [] -> 4000
        [port] -> String.to_integer(port)
        _ -> Mix.raise("usage: mix demo [port]")
      end

    Application.put_env(:formentation, FormentationDemo.Endpoint,
      adapter: Bandit.PhoenixAdapter,
      http: [ip: {127, 0, 0, 1}, port: port],
      server: true,
      secret_key_base: String.duplicate("formentation-demo-", 4),
      live_view: [signing_salt: "ftn-demo-lv"],
      pubsub_server: FormentationDemo.PubSub,
      debug_errors: true
    )

    Mix.Task.run("app.start")

    {:ok, _supervisor} =
      Supervisor.start_link(
        [
          {Phoenix.PubSub, name: FormentationDemo.PubSub},
          FormentationDemo.Endpoint
        ],
        strategy: :one_for_one
      )

    Mix.shell().info(
      "Formentation demo: http://localhost:#{port} (nested: http://localhost:#{port}/nested) — Ctrl-C stops"
    )

    Process.sleep(:infinity)
  end
end
