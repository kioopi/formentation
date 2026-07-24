defmodule Formentation.Phoenix do
  @moduledoc """
  The public rendering surface: whole-body and subtree rendering of a
  compiled definition against any `Phoenix.HTML.FormData` form. Both
  components compose *inside* an enclosing hand-written `<form>` — they
  never emit a `<form>` element, and all names and ids work under a
  parent namespace such as `asset[payload][...]` (use-case req. 5).

  Phase 1 renders through the reference theme directly; a pluggable
  theme contract is Phase 3.
  """

  use Phoenix.Component

  alias Formentation.Phoenix.{Projector, Theme.Reference}

  @doc """
  Renders the whole payload form body — error summary first, then every
  render node — inside your own `<form>`:

  ```heex
  <.form for={@asset_form} phx-change="validate" phx-submit="save">
    <.input field={@asset_form[:name]} label="Asset name" />
    <Formentation.Phoenix.fields definition={@definition} form={@payload_form} />
  </.form>
  ```

  ## Example

      iex> {:ok, definition, []} =
      ...>   Formentation.compile(
      ...>     %{kind: :object, properties: [{"email", %{kind: :string, role: :email}}]},
      ...>     adapter: Formentation.Source.Map
      ...>   )
      iex> form = Phoenix.HTML.FormData.to_form(Formentation.Form.new(definition), as: "payload")
      iex> import Phoenix.LiveViewTest
      iex> html = render_component(&Formentation.Phoenix.fields/1, definition: definition, form: form)
      iex> html =~ ~s(name="payload[email]") and not (html =~ "<form")
      true
  """
  attr(:definition, Formentation.Definition, required: true)
  attr(:form, Phoenix.HTML.Form, required: true)

  def fields(assigns) do
    assigns = assign(assigns, :plan, Projector.project(assigns.definition, assigns.form))

    ~H"""
    <div class="ftn-form">
      <Reference.error_summary summary={@plan.summary} />
      <Reference.node :for={child <- @plan.root.children} node={child} />
    </div>
    """
  end

  @doc """
  Renders the single subtree at an instance path — a field or a
  data-nesting group; presentational groups have no instance path.
  Renders nothing when the node deliberately does not render
  (hidden + read-only). Raises on unknown or unsupported paths.

  ```heex
  <Formentation.Phoenix.field
    definition={@definition}
    form={@payload_form}
    path={["address", "street"]}
  />
  ```
  """
  attr(:definition, Formentation.Definition, required: true)
  attr(:form, Phoenix.HTML.Form, required: true)

  attr(:path, :list,
    required: true,
    doc: "instance-path segments, e.g. [\"address\", \"street\"]"
  )

  def field(assigns) do
    assigns =
      assign(assigns, :node, Projector.project_at(assigns.definition, assigns.form, assigns.path))

    ~H"""
    <Reference.node :if={@node} node={@node} />
    """
  end
end
