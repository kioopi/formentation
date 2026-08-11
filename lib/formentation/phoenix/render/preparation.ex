defmodule Formentation.Phoenix.Render.Preparation do
  @moduledoc false

  alias Formentation.Definition.Semantic
  alias Formentation.{Info, InstancePath}
  alias Formentation.Info.Layout
  alias Formentation.Phoenix.DOMIdentity
  alias Formentation.Phoenix.Render.{Node, Plan}
  alias Formentation.Phoenix.Render.Preparation.{Context, Summary, Visibility, Widget}

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
  `FieldDOM` carries control/container/help/errors/option ids and `GroupDOM`
  carries container/help ids. Groups preserve their help text. Namespace
  resolution is explicit `:dom_namespace`, then `form.id || form.name`;
  projection raises if neither is available.

  ## Example

      iex> {:ok, definition, []} =
      ...>   Formentation.compile(
      ...>     %{kind: :object, properties: [{"email", %{kind: :string, role: :email}}]},
      ...>     adapter: Formentation.Source.Map
      ...>   )
      iex> form = Phoenix.HTML.FormData.to_form(%{}, as: "payload")
      iex> plan = Formentation.Phoenix.Render.Preparation.prepare(form, definition: definition)
      iex> [field] = plan.root.children
      iex> {field.widget, field.label, field.field.name}
      {:email_input, "Email", "payload[email]"}
  """
  @spec prepare(Phoenix.HTML.Form.t()) :: Plan.t()
  def prepare(%Phoenix.HTML.Form{} = form), do: prepare(form, [])

  @doc """
  Projects the whole definition with an explicit renderer-owned DOM namespace.

  ## Example

      iex> {:ok, definition, []} =
      ...>   Formentation.compile(
      ...>     %{kind: :object, properties: [{"email", %{kind: :string, role: :email}}]},
      ...>     adapter: Formentation.Source.Map
      ...>   )
      iex> form = Phoenix.HTML.FormData.to_form(%{}, as: "payload")
      iex> [field] = Formentation.Phoenix.Render.Preparation.prepare(form, definition: definition, dom_namespace: "asset_payload").root.children
      iex> {field.dom.control, field.field.name}
      {"ftn--asset_payload--field--control--email", "payload[email]"}
  """
  @spec prepare(Phoenix.HTML.Form.t(), keyword()) :: Plan.t()
  def prepare(%Phoenix.HTML.Form{} = form, opts) when is_list(opts) do
    ctx = Context.resolve(form, opts)
    descriptor = presentation_root_at(ctx.definition, ctx.root_path)
    {root, diagnostics} = project_descriptor(descriptor, form, ctx)

    %Plan{
      root: root,
      root_path: ctx.root_path,
      summary: summary(root, ctx),
      diagnostics: diagnostics
    }
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
      iex> node = Formentation.Phoenix.Render.Preparation.prepare_at(form, ["email"], definition: definition)
      iex> {node.widget, node.field.name}
      {:email_input, "payload[email]"}
  """
  @spec prepare_at(Phoenix.HTML.Form.t(), [String.t()]) ::
          Node.t() | nil
  def prepare_at(%Phoenix.HTML.Form{} = form, segments)
      when is_list(segments),
      do: prepare_at(form, segments, [])

  @doc """
  Projects one subtree with an explicit renderer-owned DOM namespace.
  """
  @spec prepare_at(Phoenix.HTML.Form.t(), [String.t()], keyword()) ::
          Node.t() | nil
  def prepare_at(%Phoenix.HTML.Form{} = form, segments, opts)
      when is_list(segments) do
    %InstancePath{segments: segments} = InstancePath.new!(segments)
    ctx = Context.resolve(form, opts)
    absolute_path = ctx.root_path ++ segments

    case Info.presentation_at(ctx.definition, absolute_path) do
      :not_found ->
        raise_path_error!("no node", segments, ctx.root_path)

      :unsupported ->
        raise_path_error!("the node is unsupported and cannot render", segments, ctx.root_path)

      {:ok, descriptor} ->
        {descent, ctx} = Context.cursor_to(ctx, descriptor_parent_path(descriptor))

        {render, _diagnostics} =
          project_descriptor(descriptor, descend(form, descent), ctx)

        render
    end
  end

  defp presentation_root_at(definition, []), do: Info.presentation_root(definition)

  defp presentation_root_at(definition, root_path) do
    case Info.presentation_at(definition, root_path) do
      {:ok, %Layout.Object{} = descriptor} ->
        descriptor

      other ->
        invariant!(
          "projection root #{inspect(root_path)} resolved to #{inspect(other)} " <>
            "after Context.resolve/2 accepted it as a projection root"
        )
    end
  end

  defp raise_path_error!(message, relative_path, []) do
    raise ArgumentError, "#{message} at instance path #{inspect(relative_path)}"
  end

  defp raise_path_error!(message, relative_path, root_path) do
    raise ArgumentError,
          "#{message} at relative path #{inspect(relative_path)} under projected root #{inspect(root_path)}"
  end

  defp descend(form, segments) do
    Enum.reduce(segments, form, fn segment, form ->
      [nested] = Phoenix.HTML.FormData.to_form(form.source, form, segment, [])
      nested
    end)
  end

  defp project_descriptor(%Layout.Object{template_path: path} = object, form, ctx) do
    {form, ctx} = object_context(object, path.segments, form, ctx)
    {children, diagnostics} = project_children(object.children, form, ctx)

    # The aligned cursor, not the descriptor's static template_path: today
    # they always agree (Phase 1 has no collections), but occurrence is
    # what a future collection item's runtime integer segment would live
    # on, and it must be the single source for both the DOM identity and
    # the occurrence_path key summary linking indexes by — so the two can
    # never drift apart from each other.
    occurrence = InstancePath.new!(ctx.path)

    dom = %Node.GroupDOM{
      container: DOMIdentity.object(ctx.dom_namespace, occurrence, :container),
      help: DOMIdentity.object(ctx.dom_namespace, occurrence, :help)
    }

    {%Node.Group{
       legend: object_legend(object),
       help: object.help,
       dom: dom,
       kind: :object,
       occurrence_path: occurrence,
       children: children
     }, diagnostics}
  end

  defp project_descriptor(%Layout.Group{} = group, form, ctx) do
    {children, diagnostics} = project_children(group.children, form, ctx)
    enclosing = InstancePath.new!(ctx.path)

    dom = %Node.GroupDOM{
      container: DOMIdentity.group(ctx.dom_namespace, group.id, enclosing, :container),
      help: DOMIdentity.group(ctx.dom_namespace, group.id, enclosing, :help)
    }

    {%Node.Group{
       legend: group_legend(group),
       help: group.help,
       dom: dom,
       kind: :presentation_group,
       occurrence_path: nil,
       children: children
     }, diagnostics}
  end

  defp project_descriptor(%Layout.Field{} = field, form, ctx) do
    case Map.fetch(ctx.semantic_nodes, field.template_path) do
      {:ok, %Semantic.Field{} = node} -> project_field(field, node, form, ctx)
      {:ok, other} -> invariant!("field descriptor resolved to #{inspect(other)}")
      :error -> invariant!("field descriptor resolved to no semantic occurrence")
    end
  end

  defp object_context(_object, path, form, ctx) do
    case Context.enter(ctx, path) do
      :self ->
        {form, ctx}

      {:child, segment, ctx} ->
        [nested] = Phoenix.HTML.FormData.to_form(form.source, form, segment, [])
        {nested, ctx}

      :error ->
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
         %Layout.Field{hidden?: true},
         %Semantic.Field{read_only?: true},
         _form,
         _ctx
       ),
       do: {nil, []}

  defp project_field(%Layout.Field{} = presentation, %Semantic.Field{} = node, form, ctx) do
    field = form[access_key(node.name)]
    {widget, diagnostics} = Widget.resolve(presentation, node)
    path = presentation.template_path.segments
    instance_path = InstancePath.new!(path)

    dom = %Node.FieldDOM{
      control: DOMIdentity.field(ctx.dom_namespace, instance_path, :control),
      container: DOMIdentity.field(ctx.dom_namespace, instance_path, :container),
      help: DOMIdentity.field(ctx.dom_namespace, instance_path, :help),
      errors: DOMIdentity.field(ctx.dom_namespace, instance_path, :errors),
      options: DOMIdentity.field_options(ctx.dom_namespace, instance_path, node.options)
    }

    {%Node.Field{
       widget: widget,
       field: field,
       label: presentation.label || humanize(node.name),
       dom: dom,
       value_type: node.value_type,
       role: node.role,
       help: presentation.help,
       options: node.options,
       validations: Phoenix.HTML.Form.input_validations(form, field.field),
       errors: field.errors,
       show_errors?: Visibility.show_errors?(field, Context.visibility_view(ctx), path),
       read_only?: node.read_only?,
       required?: node.required?
     }, diagnostics}
  end

  defp object_legend(%Layout.Object{label: label, template_path: %{segments: []}}) do
    label || "/"
  end

  defp object_legend(%Layout.Object{label: label, template_path: path}) do
    label || humanize(List.last(path.segments))
  end

  defp group_legend(%Layout.Group{label: label, id: id}) do
    label || humanize(id)
  end

  defp descriptor_parent_path(%Layout.Field{template_path: path}) do
    Enum.drop(path.segments, -1)
  end

  defp descriptor_parent_path(%Layout.Object{template_path: path}) do
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

  defp summary(root, ctx), do: Summary.build(root, Context.summary_view(ctx))
end
