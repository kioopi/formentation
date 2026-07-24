defmodule FormentationDemo.PumpInspectionLive do
  @moduledoc """
  The end-to-end example, live (phase-1 step 7): the pump-inspection
  payload form embedded in a hand-written parent form (use-case
  requirement 5), driven by `Formentation.Form.validate/2` and
  `Formentation.Form.submit/2`. A valid submit renders the decoded
  candidate as JSON — the proof that decoded submissions match the
  documented representation.
  """

  use Phoenix.LiveView

  alias Formentation.Form
  alias FormentationDemo.{LiveHelpers, PumpInspection}
  alias Phoenix.HTML.FormData

  @impl true
  def mount(_params, _session, socket) do
    {:ok, definition, _diagnostics} =
      Formentation.compile(PumpInspection.json_schema(),
        adapter: Formentation.JSONSchema,
        ui: PumpInspection.ui_hints()
      )

    {:ok,
     socket
     |> assign(
       definition: definition,
       asset_form: to_form(%{"name" => "Pump 7"}, as: :asset),
       submitted: nil,
       native_validation: true
     )
     |> assign_payload(Form.new(definition, PumpInspection.initial_data()))}
  end

  @impl true
  def handle_event("validate", %{"asset" => asset_params}, socket) do
    {:noreply,
     socket
     |> assign(:asset_form, to_form(Map.delete(asset_params, "payload"), as: :asset))
     |> assign_payload(Form.validate(socket.assigns.form_state, payload_params(asset_params)))}
  end

  def handle_event("save", %{"asset" => asset_params}, socket) do
    form_state = Form.submit(socket.assigns.form_state, payload_params(asset_params))

    {:noreply,
     socket
     |> assign(:submitted, LiveHelpers.submitted_candidate(form_state))
     |> assign_payload(form_state)}
  end

  def handle_event("toggle_native_validation", _params, socket) do
    {:noreply, update(socket, :native_validation, &(not &1))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <h1>Pump inspection</h1>
      <label>
        <input
          type="checkbox"
          id="toggle-native-validation"
          checked={@native_validation}
          phx-click="toggle_native_validation"
        /> Native browser validation
      </label>
      <.form
        for={@asset_form}
        id="asset-form"
        phx-change="validate"
        phx-submit="save"
        novalidate={not @native_validation}
      >
        <div>
          <label for={@asset_form[:name].id}>Asset name</label>
          <input
            type="text"
            id={@asset_form[:name].id}
            name={@asset_form[:name].name}
            value={@asset_form[:name].value}
          />
        </div>
        <Formentation.Phoenix.fields definition={@definition} form={@payload_form} />
        <button type="submit">Save</button>
      </.form>
      <pre :if={@submitted} id="decoded-candidate">{JSON.encode!(@submitted)}</pre>
    </main>
    """
  end

  defp payload_params(asset_params), do: Map.get(asset_params, "payload", %{})

  defp assign_payload(socket, form_state) do
    assign(socket,
      form_state: form_state,
      payload_form: FormData.to_form(form_state, as: "asset[payload]", id: "asset_payload")
    )
  end
end
