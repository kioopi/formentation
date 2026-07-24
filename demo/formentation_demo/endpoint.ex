defmodule FormentationDemo.Endpoint do
  @moduledoc """
  Minimal endpoint for the demo. Configuration comes from
  `Application.put_env/3` — `test/test_helper.exs` configures it with
  `server: false` for LiveViewTest; `mix demo` configures Bandit.
  No config/ directory exists in this library.
  """

  use Phoenix.Endpoint, otp_app: :formentation

  @session_options [
    store: :cookie,
    key: "_formentation_demo_key",
    signing_salt: "ftn-demo-session",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  plug Plug.Static, at: "/assets/phoenix", from: {:phoenix, "priv/static"}
  plug Plug.Static, at: "/assets/phoenix_live_view", from: {:phoenix_live_view, "priv/static"}

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: JSON

  plug Plug.Session, @session_options
  plug FormentationDemo.Router
end
