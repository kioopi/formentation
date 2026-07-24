defmodule FormentationDemo.Router do
  @moduledoc "Two routes: the pump-inspection demo LiveView and the nested-object demo LiveView."

  use Phoenix.Router
  import Phoenix.LiveView.Router
  import Plug.Conn
  import Phoenix.Controller

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_root_layout, html: {FormentationDemo.Layouts, :root}
  end

  scope "/", FormentationDemo do
    pipe_through :browser

    live "/", PumpInspectionLive
    live "/nested", NestedLive
  end
end
