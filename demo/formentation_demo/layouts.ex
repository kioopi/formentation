defmodule FormentationDemo.Layouts do
  @moduledoc """
  The demo's root layout: no asset pipeline — the Phoenix and LiveView
  JS ship as UMD bundles inside the deps' priv/static and are served
  by Plug.Static (see FormentationDemo.Endpoint).
  """

  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <title>Formentation demo</title>
        <script defer src="/assets/phoenix/phoenix.min.js">
        </script>
        <script defer src="/assets/phoenix_live_view/phoenix_live_view.min.js">
        </script>
        <script phx-no-curly-interpolation>
          window.addEventListener("DOMContentLoaded", () => {
            const csrfToken =
              document.querySelector("meta[name='csrf-token']").getAttribute("content")
            const liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
              params: {_csrf_token: csrfToken}
            })
            liveSocket.connect()
          })
        </script>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end
end
