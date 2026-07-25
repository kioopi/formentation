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
    port = parse_port(args)

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

    Mix.shell().info(message(port))

    Process.sleep(:infinity)
  end

  @doc """
  Resolves the HTTP port from the task arguments.

  Defaults to `4000` when no argument is given and raises a `Mix.Error`
  with a usage message when more than one argument is supplied.

  ## Examples

      iex> Mix.Tasks.Demo.parse_port([])
      4000

      iex> Mix.Tasks.Demo.parse_port(["8080"])
      8080

  """
  def parse_port([]), do: 4000
  def parse_port([port]), do: String.to_integer(port)
  def parse_port(_), do: Mix.raise("usage: mix demo [port]")

  @doc """
  Builds the startup banner naming both example URLs for `port`.

  ## Examples

      iex> Mix.Tasks.Demo.message(4000)
      "Formentation demo: http://localhost:4000 (nested: http://localhost:4000/nested) — Ctrl-C stops"

  """
  def message(port) do
    "Formentation demo: http://localhost:#{port} (nested: http://localhost:#{port}/nested) — Ctrl-C stops"
  end
end
