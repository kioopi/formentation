defmodule FormentationDemo.NestedLive do
  @moduledoc """
  The nested-object round-trip the pump-inspection example cannot show
  (its Electrical fieldset is a presentational group with flat names):
  a data-nesting `address` object, no parent form, same
  `Form.validate/2`/`Form.submit/2` handler shape.
  """

  use Phoenix.LiveView

  alias Formentation.Form
  alias Phoenix.HTML.FormData

  @schema %{
    "type" => "object",
    "required" => ["title"],
    "properties" => %{
      "title" => %{"type" => "string", "minLength" => 1},
      "address" => %{
        "type" => "object",
        "properties" => %{
          "street" => %{"type" => "string", "minLength" => 3},
          "number" => %{"type" => "integer"}
        }
      }
    }
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok, definition, _diagnostics} =
      Formentation.compile(@schema, adapter: Formentation.JSONSchema)

    {:ok,
     socket
     |> assign(definition: definition, submitted: nil)
     |> assign_payload(Form.new(definition))}
  end

  @impl true
  def handle_event("validate", %{"payload" => payload}, socket) do
    {:noreply,
     socket
     |> assign(:submitted, nil)
     |> assign_payload(Form.validate(socket.assigns.form_state, payload))}
  end

  def handle_event("save", %{"payload" => payload}, socket) do
    case Form.submit(socket.assigns.form_state, payload) do
      {:ok, candidate, submitted_form} ->
        {:noreply,
         socket
         |> assign(:submitted, candidate)
         |> assign_payload(submitted_form)}

      {:error, submitted_form} ->
        {:noreply,
         socket
         |> assign(:submitted, nil)
         |> assign_payload(submitted_form)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <h1>Nested address</h1>
      <.form for={@payload_form} id="nested-form" phx-change="validate" phx-submit="save">
        <Formentation.Phoenix.fields form={@payload_form} />
        <button type="submit">Save</button>
      </.form>
      <pre :if={@submitted} id="decoded-candidate">{JSON.encode!(@submitted)}</pre>
    </main>
    """
  end

  defp assign_payload(socket, form_state) do
    assign(socket,
      form_state: form_state,
      payload_form: FormData.to_form(form_state, as: "payload", id: "payload")
    )
  end
end
