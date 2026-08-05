defmodule Formentation.Phoenix do
  @moduledoc """
  The public rendering surface: whole-body and subtree rendering of a
  compiled definition against any `Phoenix.HTML.FormData` form. Both
  components compose *inside* an enclosing hand-written `<form>` — they
  never emit a `<form>` element. Submitted names still compose under a parent
  namespace such as `asset[payload][...]` (use-case req. 5). Renderer-owned DOM
  ids are separate: `dom_namespace`, then `form.id`, then `form.name`; rendering
  raises with guidance if none is available.

  Phase 1 renders through the reference theme directly; a pluggable
  theme contract is Phase 3.
  """

  use Phoenix.Component

  alias Formentation.Phoenix.{ReferenceComponents, RenderPlan, RenderPreparation}

  @doc """
  Renders the whole payload form body — error summary first, then every
  render node — inside your own `<form>`:

  ```heex
  <.form for={@asset_form} phx-change="validate" phx-submit="save">
    <.input field={@asset_form[:name]} label="Asset name" />
    <Formentation.Phoenix.fields form={@payload_form} />
  </.form>
  ```

  Pass `dom_namespace` only to override the namespace used for renderer-owned
  DOM ids. It does not change Phoenix field names or the enclosing form's id.

  ## Example

      iex> {:ok, definition, []} =
      ...>   Formentation.compile(
      ...>     %{kind: :object, properties: [{"email", %{kind: :string, role: :email}}]},
      ...>     adapter: Formentation.Source.Map
      ...>   )
      iex> form = Phoenix.HTML.FormData.to_form(Formentation.Form.new(definition), as: "payload")
      iex> import Phoenix.LiveViewTest
      iex> html = render_component(&Formentation.Phoenix.fields/1, form: form)
      iex> html =~ ~s(name="payload[email]") and not (html =~ "<form")
      true

  ## Generic form sources

  Any other `Phoenix.HTML.FormData` source — an `AshPhoenix.Form`, an Ecto
  changeset form, your own struct — is a permanent supported route rather than
  a compatibility shim. It cannot carry a definition, so pass one:

  ```heex
  <Formentation.Phoenix.fields definition={@definition} form={@ash_form} />
  ```

  Such a source decides submission and issue visibility through
  `Formentation.Phoenix.StateView`; without an implementation it falls back to
  the Phoenix action/`used_input?` rule.
  """
  attr(:definition, Formentation.Definition,
    default: nil,
    doc:
      "required only when `form`'s source is not a `%Formentation.Form{}`; a form " <>
        "projected from `Formentation.Form` carries its own definition, and passing " <>
        "a different one raises"
  )

  attr(:form, Phoenix.HTML.Form, required: true)
  attr(:dom_namespace, :string, default: nil, doc: "override for renderer-owned DOM ids")

  attr(:summary, :boolean,
    default: nil,
    doc:
      "whether to render the submit-gated error summary; defaults to rendering it " <>
        "only at the form's projection root, so a nested form composed under " <>
        "`<.inputs_for>` does not emit a second `role=\"alert\"` region"
  )

  def fields(assigns) do
    plan = RenderPreparation.prepare(assigns.form, preparation_opts(assigns))

    assigns =
      assigns
      |> assign(:plan, plan)
      |> assign(:summary?, summary?(assigns.summary, plan))

    ~H"""
    <div class="ftn-form">
      <ReferenceComponents.error_summary :if={@summary?} summary={@plan.summary} />
      <ReferenceComponents.node :for={child <- @plan.root.children} node={child} />
    </div>
    """
  end

  @doc """
  Renders the single subtree at an instance path — a field or a
  data-nesting group; presentational groups have no instance path.
  Renders nothing when the node deliberately does not render
  (hidden + read-only). Raises on unknown or unsupported paths. Its optional
  `dom_namespace` has the same override role as on `fields/1`.

  ```heex
  <Formentation.Phoenix.field
    form={@payload_form}
    path={["address", "street"]}
  />
  ```
  """
  attr(:definition, Formentation.Definition,
    default: nil,
    doc:
      "required only when `form`'s source is not a `%Formentation.Form{}`; a form " <>
        "projected from `Formentation.Form` carries its own definition, and passing " <>
        "a different one raises"
  )

  attr(:form, Phoenix.HTML.Form, required: true)
  attr(:dom_namespace, :string, default: nil, doc: "override for renderer-owned DOM ids")

  attr(:path, :list,
    required: true,
    doc: "instance-path segments, e.g. [\"address\", \"street\"]"
  )

  def field(assigns) do
    assigns =
      assign(
        assigns,
        :node,
        RenderPreparation.prepare_at(assigns.form, assigns.path, preparation_opts(assigns))
      )

    ~H"""
    <ReferenceComponents.node :if={@node} node={@node} />
    """
  end

  defp preparation_opts(assigns) do
    [definition: assigns.definition, dom_namespace: assigns.dom_namespace]
    |> Keyword.reject(fn {_key, value} -> is_nil(value) end)
  end

  # The error summary is a form-level affordance owned by the outermost
  # render: two role="alert" regions for one form is an accessibility
  # regression, and a nested plan's entries carry the nested form's DOM
  # namespace, so the same error would appear twice under different ids.
  # Unset therefore means "only at the projection root"; an explicit
  # true/false always wins, so a caller composing subtrees by hand decides
  # where the one summary goes.
  defp summary?(nil, %RenderPlan{root_path: root_path}), do: root_path == []
  defp summary?(summary?, _plan) when is_boolean(summary?), do: summary?
end
