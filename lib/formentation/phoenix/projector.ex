defmodule Formentation.Phoenix.Projector do
  @moduledoc """
  Combines a compiled definition with a `%Phoenix.HTML.Form{}` into a
  `Formentation.Phoenix.RenderPlan` (the rendering boundary in
  Planning/06-runtime-projection). Two-part boundary: Phoenix form
  conventions carry field-level mechanics, so any `Phoenix.HTML.FormData`
  implementation still projects; the source's
  `Formentation.Phoenix.StateView` (D-027) carries submission, issue
  visibility, and non-field issues Phoenix cannot express. Pure — same
  inputs, same plan.

  Spec: docs/superpowers/specs/2026-07-23-phase1-step6-projector-components-theme-design.md
  Spec: docs/superpowers/specs/2026-07-25-runtime-state-view-contract-design.md
  """

  alias Formentation.{Definition, Diagnostic, Info, InstancePath, Semantic}
  alias Formentation.Info.Presentation
  alias Formentation.Phoenix.{DOMIdentity, RenderNode, RenderPlan, StateView}

  @missing_namespace ~S"""
                     Formentation cannot mint DOM ids without a namespace. Give the form a name or an id
                     (`to_form(state, as: "payload")` or `to_form(state, id: "payload")`), or pass
                     `dom_namespace:` to Formentation.Phoenix.fields/1 or Formentation.Phoenix.field/1.
                     """
                     |> String.trim()

  @doc """
  Projects the whole definition against `form` into a render plan.

  The plan's root follows deterministic presentation/layout order, which
  may differ from semantic declaration order. Every field node arrives
  component-ready — resolved widget, Phoenix form
  field, label, validations, and a `show_errors?` flag decided by the
  source's `StateView` (D-027), falling back to the Phoenix
  action/`used_input?` rule (D-014) only when the source has no opinion.
  `plan.summary` is non-empty only once the source's `StateView` reports
  semantic submission. It also prepares exact renderer-owned DOM identities:
  `FieldDOM` carries control/container/help/errors/option ids and `GroupDOM` carries
  container/help ids. Namespace resolution is explicit `:dom_namespace`, then
  `form.id || form.name`; projection raises if neither is available.

  ## Example

      iex> {:ok, definition, []} =
      ...>   Formentation.compile(
      ...>     %{kind: :object, properties: [{"email", %{kind: :string, role: :email}}]},
      ...>     adapter: Formentation.Source.Map
      ...>   )
      iex> form = Phoenix.HTML.FormData.to_form(%{}, as: "payload")
      iex> plan = Formentation.Phoenix.Projector.project(definition, form)
      iex> [field] = plan.root.children
      iex> {field.widget, field.label, field.field.name}
      {:email_input, "Email", "payload[email]"}
  """
  @spec project(Definition.t(), Phoenix.HTML.Form.t()) :: RenderPlan.t()
  def project(%Definition{} = definition, %Phoenix.HTML.Form{} = form),
    do: project(definition, form, [])

  @doc """
  Projects the whole definition with an explicit renderer-owned DOM namespace.

  ## Example

      iex> {:ok, definition, []} =
      ...>   Formentation.compile(
      ...>     %{kind: :object, properties: [{"email", %{kind: :string, role: :email}}]},
      ...>     adapter: Formentation.Source.Map
      ...>   )
      iex> form = Phoenix.HTML.FormData.to_form(%{}, as: "payload")
      iex> [field] = Formentation.Phoenix.Projector.project(definition, form, dom_namespace: "asset_payload").root.children
      iex> {field.dom.control, field.field.name}
      {"ftn--asset_payload--field--control--email", "payload[email]"}
  """
  @spec project(Definition.t(), Phoenix.HTML.Form.t(), keyword()) :: RenderPlan.t()
  def project(%Definition{} = definition, %Phoenix.HTML.Form{} = form, opts) when is_list(opts) do
    ctx =
      context(
        definition,
        form,
        [],
        Info.semantic_node_index(definition),
        dom_namespace!(form, opts)
      )

    {root, diagnostics} = project_descriptor(Info.presentation_root(definition), form, ctx)
    %RenderPlan{root: root, summary: summary(root, ctx), diagnostics: diagnostics}
  end

  @doc """
  Projects the single subtree at `segments` (an instance path — fields
  and data-nesting groups; presentational groups have no instance path).
  Returns `nil` when the node deliberately renders nothing
  (hidden + read-only). Raises on unknown or unsupported paths, or when it
  cannot resolve a DOM namespace.

  ## Example

      iex> {:ok, definition, []} =
      ...>   Formentation.compile(
      ...>     %{kind: :object, properties: [{"email", %{kind: :string, role: :email}}]},
      ...>     adapter: Formentation.Source.Map
      ...>   )
      iex> form = Phoenix.HTML.FormData.to_form(%{}, as: "payload")
      iex> node = Formentation.Phoenix.Projector.project_at(definition, form, ["email"])
      iex> {node.widget, node.field.name}
      {:email_input, "payload[email]"}
  """
  @spec project_at(Definition.t(), Phoenix.HTML.Form.t(), [String.t()]) ::
          RenderNode.t() | nil
  def project_at(%Definition{} = definition, %Phoenix.HTML.Form{} = form, segments)
      when is_list(segments),
      do: project_at(definition, form, segments, [])

  @doc """
  Projects one subtree with an explicit renderer-owned DOM namespace.
  """
  @spec project_at(Definition.t(), Phoenix.HTML.Form.t(), [String.t()], keyword()) ::
          RenderNode.t() | nil
  def project_at(%Definition{} = definition, %Phoenix.HTML.Form{} = form, segments, opts)
      when is_list(segments) do
    %InstancePath{segments: segments} = InstancePath.new!(segments)

    case Info.presentation_at(definition, segments) do
      :not_found ->
        raise ArgumentError, "no node at instance path #{inspect(segments)}"

      :unsupported ->
        raise ArgumentError, "the node at #{inspect(segments)} is unsupported and cannot render"

      {:ok, descriptor} ->
        parent = descriptor_parent_path(descriptor)

        ctx =
          context(
            definition,
            form,
            parent,
            Info.semantic_node_index(definition),
            dom_namespace!(form, opts)
          )

        {render, _diagnostics} = project_descriptor(descriptor, descend(form, parent), ctx)
        render
    end
  end

  # The projection cursor. `path` holds raw segments — an %InstancePath{}
  # is built only where a path crosses into StateView — and `root_form`
  # and `source` stay pinned to the form handed to project/2 or
  # project_at/3, never a nested form built during traversal.
  defp context(definition, form, path, semantic_nodes, dom_namespace) do
    %{
      definition: definition,
      root_form: form,
      source: form.source,
      path: path,
      semantic_nodes: semantic_nodes,
      dom_namespace: dom_namespace
    }
  end

  defp descend(form, segments) do
    Enum.reduce(segments, form, fn segment, form ->
      [nested] = Phoenix.HTML.FormData.to_form(form.source, form, segment, [])
      nested
    end)
  end

  defp project_descriptor(%Presentation.Object{semantic_path: path} = object, form, ctx) do
    {form, ctx} = object_context(object, path.segments, form, ctx)
    {children, diagnostics} = project_children(object.children, form, ctx)

    dom = %RenderNode.GroupDOM{
      container: DOMIdentity.object(ctx.dom_namespace, path, :container),
      help: DOMIdentity.object(ctx.dom_namespace, path, :help)
    }

    {%RenderNode.Group{legend: object_legend(object), dom: dom, children: children}, diagnostics}
  end

  defp project_descriptor(%Presentation.Group{} = group, form, ctx) do
    {children, diagnostics} = project_children(group.children, form, ctx)
    enclosing = InstancePath.new!(ctx.path)

    dom = %RenderNode.GroupDOM{
      container: DOMIdentity.group(ctx.dom_namespace, group.id, enclosing, :container),
      help: DOMIdentity.group(ctx.dom_namespace, group.id, enclosing, :help)
    }

    {%RenderNode.Group{legend: group_legend(group), dom: dom, children: children}, diagnostics}
  end

  defp project_descriptor(%Presentation.Field{} = field, form, ctx) do
    case Map.fetch(ctx.semantic_nodes, field.semantic_path) do
      {:ok, %Semantic.Field{} = node} -> project_field(field, node, form, ctx)
      {:ok, other} -> invariant!("field descriptor resolved to #{inspect(other)}")
      :error -> invariant!("field descriptor resolved to no semantic occurrence")
    end
  end

  defp object_context(_object, path, form, %{path: path} = ctx), do: {form, ctx}

  defp object_context(_object, path, form, ctx) do
    if Enum.drop(path, -1) == ctx.path and length(path) == length(ctx.path) + 1 do
      [nested] = Phoenix.HTML.FormData.to_form(form.source, form, List.last(path), [])
      {nested, %{ctx | path: path}}
    else
      invariant!(
        "object descriptor path #{inspect(path)} is not a direct child of " <>
          "projection path #{inspect(ctx.path)}"
      )
    end
  end

  defp project_children(descriptors, form, ctx) do
    {children, diagnostics} =
      Enum.map_reduce(descriptors, [], fn descriptor, acc ->
        {child, diags} = project_descriptor(descriptor, form, ctx)
        {child, [diags | acc]}
      end)

    {Enum.reject(children, &is_nil/1), diagnostics |> Enum.reverse() |> List.flatten()}
  end

  defp project_field(
         %Presentation.Field{hidden?: true},
         %Semantic.Field{read_only?: true},
         _form,
         _ctx
       ),
       do: {nil, []}

  defp project_field(%Presentation.Field{} = presentation, %Semantic.Field{} = node, form, ctx) do
    field = form[access_key(node.name)]
    {widget, diagnostics} = resolve_widget(presentation, node)
    path = presentation.semantic_path.segments
    instance_path = presentation.semantic_path

    dom = %RenderNode.FieldDOM{
      control: DOMIdentity.field(ctx.dom_namespace, instance_path, :control),
      container: DOMIdentity.field(ctx.dom_namespace, instance_path, :container),
      help: DOMIdentity.field(ctx.dom_namespace, instance_path, :help),
      errors: DOMIdentity.field(ctx.dom_namespace, instance_path, :errors),
      options: option_ids(node.options, ctx.dom_namespace, instance_path)
    }

    {%RenderNode.Field{
       widget: widget,
       field: field,
       label: presentation.label || humanize(node.name),
       dom: dom,
       help: presentation.help,
       options: node.options,
       validations: Phoenix.HTML.Form.input_validations(form, field.field),
       errors: field.errors,
       show_errors?: show_errors?(field, ctx, path),
       read_only?: node.read_only?
     }, diagnostics}
  end

  # Spec order: hidden -> hint -> options -> boolean -> number -> role -> text.
  defp resolve_widget(%Presentation.Field{hidden?: true}, _node), do: {:hidden_input, []}
  defp resolve_widget(%Presentation.Field{widget: nil}, node), do: {infer_widget(node), []}

  defp resolve_widget(%Presentation.Field{widget: hint}, node) do
    case hinted_widget(hint, node) do
      {:ok, widget} ->
        {widget, []}

      :fallback ->
        widget = infer_widget(node)
        {widget, [fallback_diagnostic(hint, node, widget)]}
    end
  end

  defp hinted_widget(:text, _node), do: {:ok, :text_input}
  defp hinted_widget(:textarea, _node), do: {:ok, :textarea}
  defp hinted_widget(:select, %Semantic.Field{options: [_ | _]}), do: {:ok, :select}
  defp hinted_widget(:radio, %Semantic.Field{options: [_ | _]}), do: {:ok, :radio_group}
  defp hinted_widget(:checkbox, %Semantic.Field{value_type: :boolean}), do: {:ok, :checkbox}
  defp hinted_widget(_hint, _node), do: :fallback

  defp infer_widget(%Semantic.Field{options: [_ | _]}), do: :select
  defp infer_widget(%Semantic.Field{value_type: :boolean}), do: :checkbox

  defp infer_widget(%Semantic.Field{value_type: type}) when type in [:integer, :number],
    do: :number_input

  defp infer_widget(%Semantic.Field{role: :date}), do: :date_input
  defp infer_widget(%Semantic.Field{role: :email}), do: :email_input
  defp infer_widget(%Semantic.Field{role: :uri}), do: :url_input
  defp infer_widget(%Semantic.Field{}), do: :text_input

  defp option_ids(nil, _namespace, _path), do: []
  defp option_ids([], _namespace, _path), do: []

  defp option_ids(options, namespace, path) do
    Enum.map(Enum.with_index(options), fn {_option, index} ->
      DOMIdentity.field(namespace, path, {:option, index})
    end)
  end

  defp fallback_diagnostic(hint, node, widget) do
    %Diagnostic{
      severity: :warning,
      code: :widget_fallback,
      message:
        "widget #{inspect(hint)} cannot render field #{inspect(node.name)}; " <>
          "falling back to #{inspect(widget)}",
      template_path: node.template_path
    }
  end

  defp object_legend(%Presentation.Object{label: label, semantic_path: %{segments: []}}) do
    label || "/"
  end

  defp object_legend(%Presentation.Object{label: label, semantic_path: path}) do
    label || humanize(List.last(path.segments))
  end

  defp group_legend(%Presentation.Group{label: label, id: id}) do
    label || humanize(id)
  end

  defp descriptor_parent_path(%Presentation.Field{semantic_path: path}) do
    Enum.drop(path.segments, -1)
  end

  defp descriptor_parent_path(%Presentation.Object{semantic_path: path}) do
    Enum.drop(path.segments, -1)
  end

  defp invariant!(message),
    do: raise(ArgumentError, "invalid presentation descriptor: " <> message)

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

  # D-014, now source-owned: the state view decides, and only falls back
  # to the Phoenix-compatible default when it answers :default. Computed
  # here, once, so themes never see markers or actions.
  defp show_errors?(field, ctx, path) do
    field.errors != [] and
      visible?(ctx, path, fn -> submitted?(ctx) or Phoenix.Component.used_input?(field) end)
  end

  defp visible?(ctx, path, default_fun) do
    case StateView.issue_visibility(ctx.source, ctx.root_form, InstancePath.new!(path)) do
      :show -> true
      :hide -> false
      :default -> default_fun.()
    end
  end

  defp submitted?(ctx), do: StateView.submitted?(ctx.source, ctx.root_form)

  defp summary(root, ctx) do
    if submitted?(ctx) do
      field_entries(root) ++ non_field_entries(ctx)
    else
      []
    end
  end

  defp field_entries(%RenderNode.Group{children: children}) do
    Enum.flat_map(children, &field_entries/1)
  end

  defp field_entries(%RenderNode.Field{show_errors?: true} = node) do
    for {message, _opts} <- node.errors do
      summary_entry(summary_target(node), node.label, message)
    end
  end

  defp field_entries(%RenderNode.Field{}), do: []

  defp summary_target(%RenderNode.Field{widget: widget, dom: dom}),
    do: Map.fetch!(dom, summary_part(widget))

  # Reference-theme contract: every widget must appear here. Composite widgets
  # target the element their component renders as the group-level control;
  # scalar widgets target their control.
  defp summary_part(:radio_group), do: :container

  defp summary_part(widget)
       when widget in [
              :hidden_input,
              :checkbox,
              :textarea,
              :select,
              :number_input,
              :date_input,
              :email_input,
              :url_input,
              :text_input
            ],
       do: :control

  # Root, group and unsupported-node issues never enter Phoenix's per-field
  # error convention (step-5 spec decision 7), so they arrive normalized
  # from the state view instead. Adapter order is authoritative — the
  # projector filters but never reorders. A source with no enumeration
  # capability degrades to the scalar entries above rather than guessing.
  defp non_field_entries(ctx) do
    case StateView.issues(ctx.source, ctx.root_form) do
      :unavailable ->
        []

      {:ok, issues} ->
        issues
        |> Enum.filter(&non_field_visible?(ctx, &1))
        |> Enum.map(&summary_entry(nil, summary_label(ctx, &1.path), &1.message))
    end
  end

  # Unlike visible?/3 (used for fields), :default counts as visible here:
  # non_field_entries/1 only runs from summary/2 once submitted?(ctx) is
  # already true, so the submission gate is already applied and there is
  # no per-entry Phoenix default left to apply — only an explicit :hide
  # suppresses an entry.
  defp non_field_visible?(ctx, %StateView.Issue{path: path}) do
    not field_path?(ctx, path) and
      StateView.issue_visibility(ctx.source, ctx.root_form, path) != :hide
  end

  defp field_path?(ctx, %InstancePath{segments: segments}) do
    Info.semantic_kind(ctx.definition, segments) == :field
  end

  # An unsupported node carries a name a reader can recognize, so its
  # entry is worth labelling; root and group issues stay unlabelled, as
  # they were before D-027.
  defp summary_label(ctx, %InstancePath{segments: segments}) do
    case Info.semantic_kind(ctx.definition, segments) do
      :unsupported -> humanize(List.last(segments))
      _root_object_or_unknown -> nil
    end
  end

  defp summary_entry(id, label, message), do: %{id: id, label: label, message: message}

  defp dom_namespace!(form, opts) do
    Keyword.get(opts, :dom_namespace) || form.id || form.name ||
      raise ArgumentError, @missing_namespace
  end
end
