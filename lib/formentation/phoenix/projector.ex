defmodule Formentation.Phoenix.Projector do
  @moduledoc """
  Combines a compiled definition with a `%Phoenix.HTML.Form{}` into a
  `Formentation.Phoenix.RenderPlan` (the rendering boundary in
  Planning/06-runtime-projection). Phoenix-generic: state is read only
  through the Phoenix form conventions, so any `Phoenix.HTML.FormData`
  implementation projects. Pure — same inputs, same plan.

  Spec: docs/superpowers/specs/2026-07-23-phase1-step6-projector-components-theme-design.md
  """

  alias Formentation.{Definition, Diagnostic, Form, Info, Node}
  alias Formentation.Phoenix.{RenderNode, RenderPlan}

  @doc """
  Projects the whole definition against `form` into a render plan.

  The plan's root mirrors the compiled tree in declaration order; every
  field node arrives component-ready — resolved widget, Phoenix form
  field, label, validations, and a `show_errors?` flag that already
  folds usage and action (D-014). `plan.summary` is non-empty only after
  a submit.

  ## Example

      iex> {:ok, definition, []} =
      ...>   Formentation.compile(
      ...>     %{kind: :object, properties: [{"email", %{kind: :string, role: :email}}]},
      ...>     adapter: Formentation.Source.Map
      ...>   )
      iex> form = Phoenix.HTML.FormData.to_form(Formentation.Form.new(definition), as: "payload")
      iex> plan = Formentation.Phoenix.Projector.project(definition, form)
      iex> [field] = plan.root.children
      iex> {field.widget, field.label, field.field.name}
      {:email_input, "Email", "payload[email]"}
  """
  @spec project(Definition.t(), Phoenix.HTML.Form.t()) :: RenderPlan.t()
  def project(%Definition{} = definition, %Phoenix.HTML.Form{} = form) do
    {root, diagnostics} = project_group(Info.root(definition), form)
    %RenderPlan{root: root, summary: summary(root, form), diagnostics: diagnostics}
  end

  @doc """
  Projects the single subtree at `segments` (an instance path — fields
  and data-nesting groups; presentational groups have no instance path).
  Returns `nil` when the node deliberately renders nothing
  (hidden + read-only). Raises on unknown or unsupported paths.

  ## Example

      iex> {:ok, definition, []} =
      ...>   Formentation.compile(
      ...>     %{kind: :object, properties: [{"email", %{kind: :string, role: :email}}]},
      ...>     adapter: Formentation.Source.Map
      ...>   )
      iex> form = Phoenix.HTML.FormData.to_form(Formentation.Form.new(definition), [])
      iex> node = Formentation.Phoenix.Projector.project_at(definition, form, ["email"])
      iex> {node.widget, node.field.name}
      {:email_input, "email"}
  """
  @spec project_at(Definition.t(), Phoenix.HTML.Form.t(), [String.t()]) ::
          RenderNode.t() | nil
  def project_at(%Definition{} = definition, %Phoenix.HTML.Form{} = form, segments)
      when is_list(segments) do
    case Info.node_at(definition, segments) do
      nil ->
        raise ArgumentError, "no node at instance path #{inspect(segments)}"

      %Node.Unsupported{} ->
        raise ArgumentError, "the node at #{inspect(segments)} is unsupported and cannot render"

      node ->
        {render, _diagnostics} = project_node(node, descend(form, Enum.drop(segments, -1)))
        render
    end
  end

  defp descend(form, segments) do
    Enum.reduce(segments, form, fn segment, form ->
      [nested] = Phoenix.HTML.FormData.to_form(form.source, form, segment, [])
      nested
    end)
  end

  defp project_group(%Node.Group{} = group, form) do
    {children, diagnostics} = project_children(group.children, form)
    {%RenderNode.Group{legend: legend(group), children: children}, diagnostics}
  end

  defp project_children(nodes, form) do
    {children, diagnostics} =
      Enum.map_reduce(nodes, [], fn node, acc ->
        {child, diags} = project_node(node, form)
        {child, [diags | acc]}
      end)

    {Enum.reject(children, &is_nil/1), diagnostics |> Enum.reverse() |> List.flatten()}
  end

  defp project_node(%Node.Field{hidden?: true, read_only?: true}, _form), do: {nil, []}
  defp project_node(%Node.Field{} = node, form), do: project_field(node, form)
  defp project_node(%Node.Unsupported{}, _form), do: {nil, []}

  defp project_node(%Node.Group{nests_data?: false} = group, form) do
    project_group(group, form)
  end

  defp project_node(%Node.Group{nests_data?: true} = group, form) do
    [nested] = Phoenix.HTML.FormData.to_form(form.source, form, group.name, [])
    project_group(group, nested)
  end

  defp project_field(%Node.Field{} = node, form) do
    field = form[access_key(node.name)]
    {widget, diagnostics} = resolve_widget(node)

    {%RenderNode.Field{
       widget: widget,
       field: field,
       label: node.label || humanize(node.name),
       help: node.help,
       options: node.options,
       validations: Phoenix.HTML.Form.input_validations(form, field.field),
       errors: field.errors,
       show_errors?: show_errors?(field, form),
       read_only?: node.read_only?
     }, diagnostics}
  end

  # Spec order: hidden -> hint -> options -> boolean -> number -> role -> text.
  defp resolve_widget(%Node.Field{hidden?: true}), do: {:hidden_input, []}
  defp resolve_widget(%Node.Field{widget: nil} = node), do: {infer_widget(node), []}

  defp resolve_widget(%Node.Field{widget: hint} = node) do
    case hinted_widget(hint, node) do
      {:ok, widget} ->
        {widget, []}

      :fallback ->
        widget = infer_widget(node)
        {widget, [fallback_diagnostic(node, widget)]}
    end
  end

  defp hinted_widget(:text, _node), do: {:ok, :text_input}
  defp hinted_widget(:textarea, _node), do: {:ok, :textarea}
  defp hinted_widget(:select, %Node.Field{options: [_ | _]}), do: {:ok, :select}
  defp hinted_widget(:radio, %Node.Field{options: [_ | _]}), do: {:ok, :radio_group}
  defp hinted_widget(:checkbox, %Node.Field{value_type: :boolean}), do: {:ok, :checkbox}
  defp hinted_widget(_hint, _node), do: :fallback

  defp infer_widget(%Node.Field{options: [_ | _]}), do: :select
  defp infer_widget(%Node.Field{value_type: :boolean}), do: :checkbox

  defp infer_widget(%Node.Field{value_type: type}) when type in [:integer, :number],
    do: :number_input

  defp infer_widget(%Node.Field{role: :date}), do: :date_input
  defp infer_widget(%Node.Field{role: :email}), do: :email_input
  defp infer_widget(%Node.Field{role: :uri}), do: :url_input
  defp infer_widget(%Node.Field{}), do: :text_input

  defp fallback_diagnostic(node, widget) do
    %Diagnostic{
      severity: :warning,
      code: :widget_fallback,
      message:
        "widget #{inspect(node.widget)} cannot render field #{inspect(node.name)}; " <>
          "falling back to #{inspect(widget)}",
      template_path: node.template_path
    }
  end

  defp legend(%Node.Group{label: label, name: name, id: id}) do
    label || humanize(name || id)
  end

  # Mirrors the FormData error_key convention (step-5 spec decision 4):
  # errors key by existing atom, so field access must use the atom when
  # it exists — otherwise form["name"].errors is [] while the error sits
  # under :name. to_existing_atom never creates an atom.
  defp access_key(name) do
    String.to_existing_atom(name)
  rescue
    ArgumentError -> name
  end

  defp humanize(name) do
    name |> String.replace("_", " ") |> String.capitalize()
  end

  # D-014: an issue renders when the form's action is submit or the
  # field's usage is :used — computed here, once, the Phoenix way, so
  # any FormData source gets the same rule and themes never see markers.
  defp show_errors?(field, form) do
    field.errors != [] and (form.action == :submit or Phoenix.Component.used_input?(field))
  end

  defp summary(root, %Phoenix.HTML.Form{action: :submit} = form) do
    field_entries(root) ++ object_entries(form.source)
  end

  defp summary(_root, _form), do: []

  defp field_entries(%RenderNode.Group{children: children}) do
    Enum.flat_map(children, &field_entries/1)
  end

  defp field_entries(%RenderNode.Field{show_errors?: true} = node) do
    for {message, _opts} <- node.errors do
      %{id: node.field.id, label: node.label, message: message}
    end
  end

  defp field_entries(%RenderNode.Field{}), do: []

  # Root and object-level issues never enter Phoenix's per-field errors
  # (step-5 spec decision 7). When the source is a Formentation.Form we
  # can reach them for the summary; other FormData sources degrade to
  # the per-field entries above.
  defp object_entries(%Form{} = form_state) do
    form_state.issues
    |> Enum.reject(fn {path, _issues} ->
      match?(%Node.Field{}, Info.node_at(form_state.definition, path.segments))
    end)
    |> Enum.sort_by(fn {path, _issues} -> path.segments end)
    |> Enum.flat_map(fn {_path, issues} ->
      for issue <- issues, do: %{id: nil, label: nil, message: issue.message}
    end)
  end

  defp object_entries(_source), do: []
end
