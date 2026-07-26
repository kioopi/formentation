defmodule Formentation.Source.Map do
  @moduledoc """
  Plain Elixir data declaration source — the reference adapter and
  cheapest fixture format (D-004). Lives in core with zero dependencies.

  A declaration is a map with a `:kind`. Object properties are an ordered
  list of `{name, spec}` tuples, so ordering is data, never map
  enumeration order.
  """

  @behaviour Formentation.Source

  alias Formentation.{Definition, Diagnostic, Node, NodeId, Presentation, Semantic, TemplatePath}
  alias Formentation.Definition.Finalizer
  alias Formentation.Source.Shared

  defmodule Compiled do
    @moduledoc false

    defstruct [:legacy, :semantic, :presentation]
  end

  defmodule PresentationGroupSpec do
    @moduledoc false

    defstruct [:id, :label, :label_origin, :fields]
  end

  @scalar_kinds [:string, :integer, :number, :boolean]

  @constraint_keys [:min_length, :max_length, :min, :max]

  @role_defaults %{
    string: {:text, :string_default},
    integer: {:integer, :integer_default},
    number: {:number, :number_default},
    boolean: {:boolean, :boolean_default}
  }

  @doc """
  Compiles a map declaration. Options: `:max_depth` (default 16) and
  `:max_nodes` (default 1000) budget overrides.
  """
  @impl true
  def compile(declaration, opts \\ []) do
    ctx = %Shared.Context{
      max_depth: Keyword.get(opts, :max_depth, 16),
      nodes_left: Keyword.get(opts, :max_nodes, 1_000)
    }

    case compile_object(declaration, nil, ctx) do
      {:ok, %Compiled{} = compiled, ctx} ->
        {:ok, %Definition{} = legacy_definition, diagnostics} =
          Shared.finalize_legacy(compiled.legacy, ctx)

        {:ok, native_definition} =
          Finalizer.finalize(compiled.semantic, compiled.presentation, diagnostics: diagnostics)

        definition = %Definition{
          legacy_definition
          | semantic: native_definition.semantic,
            semantic_index: native_definition.semantic_index,
            presentation: native_definition.presentation
        }

        {:ok, definition, diagnostics}

      {:error, %Diagnostic{} = diagnostic} ->
        {:error, [diagnostic]}
    end
  end

  defp compile_object(%{kind: :object} = declaration, name, ctx) do
    with :ok <- check_depth(ctx),
         {:ok, ctx} <- take_budget(ctx),
         {:ok, required} <- fetch_list(declaration, :required, ctx),
         {:ok, children, ctx} <- compile_children(declaration, required, ctx),
         {:ok, groups} <- fetch_groups(declaration, ctx) do
      legacy_children = Enum.map(children, & &1.legacy)
      legacy_children = Shared.stamp_declaration_order(legacy_children)
      {legacy_children, ctx} = attach_groups(legacy_children, groups, ctx)

      semantic_children = Enum.map(children, & &1.semantic)
      {presentation_children, ctx} = attach_presentation_groups(children, groups, ctx)

      {label, label_origin} = resolve_label(declaration, name, ctx.source_path)

      presentation_origins =
        Shared.origin_entries(
          label: label_origin,
          help: key_origin(declaration, :help, ctx.source_path)
        )

      legacy =
        Shared.create_group_node(name, legacy_children, ctx,
          label: label,
          label_origin: label_origin,
          help: declaration[:help],
          help_origin: key_origin(declaration, :help, ctx.source_path)
        )

      semantic =
        Semantic.Object.new(name, ctx.template_path, semantic_children, origins: [])

      presentation =
        Presentation.Object.new(semantic.id, presentation_children,
          id: Presentation.object_id(semantic.id),
          label: label,
          help: declaration[:help],
          origins: presentation_origins
        )

      {:ok, %Compiled{legacy: legacy, semantic: semantic, presentation: presentation}, ctx}
    end
  end

  defp compile_object(declaration, _name, ctx) do
    {:error, invalid("expected an object declaration, got: #{inspect(declaration)}", ctx)}
  end

  defp check_depth(%Shared.Context{depth: depth, max_depth: max_depth} = ctx)
       when depth > max_depth do
    {:error,
     budget_diagnostic(
       :max_depth_exceeded,
       "declaration exceeds maximum depth of #{max_depth}",
       ctx
     )}
  end

  defp check_depth(_ctx), do: :ok

  defp take_budget(%Shared.Context{nodes_left: nodes_left} = ctx) when nodes_left <= 0 do
    {:error, budget_diagnostic(:max_nodes_exceeded, "declaration node budget exhausted", ctx)}
  end

  defp take_budget(%Shared.Context{nodes_left: nodes_left} = ctx) do
    {:ok, %{ctx | nodes_left: nodes_left - 1}}
  end

  defp budget_diagnostic(code, message, ctx) do
    %Diagnostic{
      severity: :error,
      code: code,
      message: message,
      origin: {:map_source, ctx.source_path},
      template_path: ctx.template_path
    }
  end

  defp compile_children(declaration, required, ctx) do
    with {:ok, properties} <- fetch_list(declaration, :properties, ctx) do
      compile_properties(properties, required, ctx)
    end
  end

  defp compile_properties(properties, required, ctx) do
    with :ok <- reject_duplicate_properties(properties, ctx),
         {:ok, compiled, ctx} <- compile_properties_in_order(properties, required, ctx) do
      {:ok, Enum.reverse(compiled), ctx}
    end
  end

  defp compile_properties_in_order(properties, required, ctx) do
    Enum.reduce_while(properties, {:ok, [], ctx}, fn {prop_name, spec}, {:ok, acc, ctx} ->
      case compile_property(prop_name, spec, prop_name in required, ctx) do
        {:ok, node, ctx} -> {:cont, {:ok, [node | acc], ctx}}
        {:error, diagnostic} -> {:halt, {:error, diagnostic}}
      end
    end)
  end

  defp reject_duplicate_properties(properties, ctx) do
    {_seen, duplicate} =
      Enum.reduce_while(properties, {MapSet.new(), nil}, fn {name, _spec}, {seen, nil} ->
        if MapSet.member?(seen, name) do
          {:halt, {seen, name}}
        else
          {:cont, {MapSet.put(seen, name), nil}}
        end
      end)

    case duplicate do
      nil -> :ok
      name -> {:error, duplicate_property(name, ctx)}
    end
  end

  defp duplicate_property(name, ctx) do
    %Diagnostic{
      severity: :error,
      code: :duplicate_property,
      message: "duplicate property #{inspect(name)}",
      origin: {:map_source, ctx.source_path ++ [:properties, name]},
      template_path: TemplatePath.child(ctx.template_path, name)
    }
  end

  defp fetch_list(declaration, key, ctx) do
    case Map.get(declaration, key, []) do
      list when is_list(list) ->
        {:ok, list}

      other ->
        {:error, invalid("#{key}: expected a list, got: #{inspect(other)}", ctx)}
    end
  end

  defp fetch_groups(declaration, ctx) do
    with {:ok, groups} <- fetch_list(declaration, :groups, ctx) do
      validate_groups(groups, ctx)
    end
  end

  defp validate_groups(groups, ctx) do
    groups
    |> Enum.reduce_while({:ok, []}, fn
      %{id: _id, fields: _fields} = group, {:ok, acc} ->
        {:cont, {:ok, [group | acc]}}

      other, _acc ->
        {:halt,
         {:error, invalid("group declaration missing :id or :fields: #{inspect(other)}", ctx)}}
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      {:error, diagnostic} -> {:error, diagnostic}
    end
  end

  defp compile_property(name, %{kind: :object} = spec, required?, ctx) do
    child_ctx = %{
      ctx
      | depth: ctx.depth + 1,
        template_path: TemplatePath.child(ctx.template_path, name),
        source_path: ctx.source_path ++ [:properties, name]
    }

    with {:ok, %Compiled{} = compiled, child_ctx} <- compile_object(spec, name, child_ctx) do
      {:ok,
       %Compiled{
         compiled
         | legacy: %{compiled.legacy | required?: required?},
           semantic: %{compiled.semantic | required?: required?}
       }, %{ctx | diagnostics: child_ctx.diagnostics, nodes_left: child_ctx.nodes_left}}
    end
  end

  defp compile_property(name, %{kind: kind} = spec, required?, ctx) when kind in @scalar_kinds do
    compile_field(name, spec, required?, ctx)
  end

  defp compile_property(name, %{kind: kind}, required?, ctx) do
    with {:ok, ctx} <- take_budget(ctx) do
      template_path = TemplatePath.child(ctx.template_path, name)
      source_path = ctx.source_path ++ [:properties, name]

      legacy = %Node.Unsupported{
        id: NodeId.from_path(template_path),
        name: name,
        required?: required?,
        template_path: template_path,
        origins: Shared.origin_entries(kind: {:map_source, source_path ++ [:kind]})
      }

      semantic =
        Semantic.Unsupported.new(name, template_path,
          required?: required?,
          origins: legacy.origins
        )

      diagnostic = %Diagnostic{
        severity: :warning,
        code: :unsupported_kind,
        message: "unsupported kind #{inspect(kind)} for property #{inspect(name)}",
        origin: {:map_source, source_path ++ [:kind]},
        template_path: template_path
      }

      {:ok, %Compiled{legacy: legacy, semantic: semantic, presentation: nil},
       %{ctx | diagnostics: [diagnostic | ctx.diagnostics]}}
    end
  end

  defp compile_property(name, spec, _required?, ctx) do
    {:error, invalid("property #{inspect(name)} has no kind: #{inspect(spec)}", ctx)}
  end

  defp compile_field(name, %{kind: kind} = spec, required?, ctx) when kind in @scalar_kinds do
    template_path = TemplatePath.child(ctx.template_path, name)
    source_path = ctx.source_path ++ [:properties, name]

    with {:ok, ctx} <- take_budget(ctx),
         {:ok, examples, examples_origin} <- fetch_examples(spec, name, source_path, ctx) do
      {label, label_origin} = resolve_label(spec, name, source_path)
      {role, role_origin} = resolve_role(spec, source_path)

      {default, default_origin, ctx} =
        resolve_default(spec, name, source_path, template_path, ctx)

      {hidden, hidden_origin, ctx} =
        resolve_flag(spec, :hidden, name, source_path, template_path, ctx)

      {read_only, read_only_origin, ctx} =
        resolve_flag(spec, :read_only, name, source_path, template_path, ctx)

      origins =
        Shared.origin_entries(
          label: label_origin,
          role: role_origin,
          widget: key_origin(spec, :widget, source_path),
          help: key_origin(spec, :help, source_path),
          options: options_origin(spec, source_path),
          examples: examples_origin,
          default: default_origin,
          hidden: hidden_origin,
          read_only: read_only_origin
        )

      legacy = %Node.Field{
        id: NodeId.from_path(template_path),
        name: name,
        label: label,
        role: role,
        value_type: kind,
        template_path: template_path,
        required?: required?,
        hidden?: hidden,
        read_only?: read_only,
        options: one_of_options(spec),
        help: spec[:help],
        widget: spec[:widget],
        default: default,
        examples: examples,
        constraints: Map.take(spec, @constraint_keys),
        origins: origins
      }

      semantic =
        Semantic.Field.new(name, template_path, kind,
          role: role,
          required?: required?,
          read_only?: read_only,
          options: one_of_options(spec),
          default: default,
          examples: examples,
          constraints: Map.take(spec, @constraint_keys),
          origins: semantic_origins(origins)
        )

      presentation =
        Presentation.Field.new(semantic.id,
          id: Presentation.field_id(semantic.id),
          label: label,
          help: spec[:help],
          widget: spec[:widget],
          hidden?: hidden,
          origins: presentation_origins(origins)
        )

      {:ok, %Compiled{legacy: legacy, semantic: semantic, presentation: presentation}, ctx}
    end
  end

  defp fetch_examples(spec, name, source_path, ctx) do
    case Map.fetch(spec, :examples) do
      {:ok, examples} when is_list(examples) ->
        {:ok, examples, {:map_source, source_path ++ [:examples]}}

      {:ok, other} ->
        {:error,
         invalid(
           "property #{inspect(name)} examples: expected a list, got: #{inspect(other)}",
           ctx,
           source_path ++ [:examples]
         )}

      :error ->
        {:ok, nil, nil}
    end
  end

  defp resolve_default(spec, name, source_path, template_path, ctx) do
    case Map.fetch(spec, :default) do
      {:ok, nil} ->
        warning = %Diagnostic{
          severity: :warning,
          code: :unsupported_keyword,
          message: "nil default for property #{inspect(name)} is ignored",
          origin: {:map_source, source_path ++ [:default]},
          template_path: template_path
        }

        {nil, nil, %{ctx | diagnostics: [warning | ctx.diagnostics]}}

      {:ok, value} ->
        {value, {:map_source, source_path ++ [:default]}, ctx}

      :error ->
        {nil, nil, ctx}
    end
  end

  defp resolve_flag(spec, key, name, source_path, template_path, ctx) do
    case Map.fetch(spec, key) do
      {:ok, value} when is_boolean(value) ->
        {value, {:map_source, source_path ++ [key]}, ctx}

      {:ok, other} ->
        warning = %Diagnostic{
          severity: :warning,
          code: :invalid_hint_value,
          message:
            "#{key} for property #{inspect(name)} must be a boolean, " <>
              "got: #{inspect(other)}; ignored",
          origin: {:map_source, source_path ++ [key]},
          template_path: template_path
        }

        {false, nil, %{ctx | diagnostics: [warning | ctx.diagnostics]}}

      :error ->
        {false, nil, ctx}
    end
  end

  defp invalid(message, ctx, origin_path \\ nil) do
    %Diagnostic{
      severity: :error,
      code: :invalid_declaration,
      message: message,
      origin: {:map_source, origin_path || ctx.source_path},
      template_path: ctx.template_path
    }
  end

  defp resolve_label(%{title: title}, _name, source_path) when is_binary(title) do
    {title, {:map_source, source_path ++ [:title]}}
  end

  defp resolve_label(_spec, nil, _source_path), do: {nil, nil}

  defp resolve_label(_spec, name, _source_path) do
    {Shared.humanize(name), {:inference, :label_from_name}}
  end

  defp resolve_role(%{role: role}, source_path) when not is_nil(role) do
    {role, {:map_source, source_path ++ [:role]}}
  end

  defp resolve_role(%{one_of: options}, _source_path) when is_list(options) do
    {:select, {:inference, :one_of_select}}
  end

  defp resolve_role(%{kind: kind}, _source_path) do
    {role, rule} = Map.fetch!(@role_defaults, kind)
    {role, {:inference, rule}}
  end

  defp key_origin(spec, key, source_path) do
    if Map.has_key?(spec, key), do: {:map_source, source_path ++ [key]}
  end

  defp one_of_options(%{one_of: options}) when is_list(options), do: options
  defp one_of_options(_spec), do: nil

  defp options_origin(%{one_of: options}, source_path) when is_list(options) do
    {:map_source, source_path ++ [:one_of]}
  end

  defp options_origin(_spec, _source_path), do: nil

  @semantic_origin_keys [:role, :options, :examples, :default, :read_only]
  @presentation_origin_keys [:label, :widget, :help, :hidden]

  defp semantic_origins(origins), do: filter_origins(origins, @semantic_origin_keys)
  defp presentation_origins(origins), do: filter_origins(origins, @presentation_origin_keys)

  defp filter_origins(origins, allowed_keys) do
    Enum.filter(origins, fn {key, _origin} -> key in allowed_keys end)
  end

  defp attach_groups(children, groups, ctx) do
    Enum.reduce(groups, {children, ctx}, &attach_group/2)
  end

  defp attach_group(%{id: id, fields: member_names} = group, {children, ctx}) do
    {label, label_origin} = group_label(group, ctx.source_path)
    spec = %{id: id, label: label, label_origin: label_origin, fields: member_names}

    {children, unknown} = Shared.attach_group(children, spec, ctx.template_path)
    ctx = warn_unknown_members(unknown, id, ctx)

    {children, ctx}
  end

  defp attach_presentation_groups(compiled_children, groups, ctx) do
    children = compiled_children |> Enum.map(& &1.presentation) |> Enum.reject(&is_nil/1)
    Enum.reduce(groups, {children, ctx}, &attach_presentation_group(&1, &2, compiled_children))
  end

  defp attach_presentation_group(
         %{id: id, fields: member_names} = group,
         {children, ctx},
         compiled_children
       ) do
    {label, label_origin} = group_label(group, ctx.source_path)

    spec = %PresentationGroupSpec{
      id: id,
      label: label,
      label_origin: label_origin,
      fields: member_names
    }

    {children, _unknown_already_warned_by_legacy_layout} =
      attach_presentation_group(children, compiled_children, spec, ctx.template_path)

    {children, ctx}
  end

  defp attach_presentation_group(
         children,
         compiled_children,
         %PresentationGroupSpec{fields: field_names} = spec,
         template_path
       ) do
    field_names = Enum.uniq(field_names)
    compiled_by_name = Map.new(compiled_children, &{&1.semantic.name, &1})
    presentation_by_name = Map.new(compiled_children, &{&1.semantic.name, &1.presentation})
    unknown = Enum.reject(field_names, &is_map_key(compiled_by_name, &1))

    members =
      field_names
      |> Enum.filter(&is_map_key(compiled_by_name, &1))
      |> Enum.map(&Map.fetch!(presentation_by_name, &1))
      |> Enum.reject(&is_nil/1)

    {place_presentation_group(children, spec, members, template_path), unknown}
  end

  defp place_presentation_group(children, _spec, [], _template_path), do: children

  defp place_presentation_group(
         children,
         %PresentationGroupSpec{id: id} = spec,
         members,
         template_path
       ) do
    group =
      Presentation.Group.new(id, members,
        layout_id: NodeId.group(template_path, id),
        label: spec.label,
        origins: Shared.origin_entries(label: spec.label_origin)
      )

    member_ids = MapSet.new(members, & &1.semantic_id)
    first_index = Enum.find_index(children, &(presentation_reference_id(&1) in member_ids))

    children
    |> Enum.reject(&(presentation_reference_id(&1) in member_ids))
    |> List.insert_at(first_index, group)
  end

  defp presentation_reference_id(%Presentation.Field{semantic_id: semantic_id}), do: semantic_id
  defp presentation_reference_id(%Presentation.Object{semantic_id: semantic_id}), do: semantic_id
  defp presentation_reference_id(%Presentation.Group{}), do: nil

  defp group_label(%{id: id, title: title}, source_path) when is_binary(title) do
    {title, {:map_source, source_path ++ [:groups, id, :title]}}
  end

  defp group_label(_group, _source_path), do: {nil, nil}

  defp warn_unknown_members(unknown_names, group_id, ctx) do
    origin = {:map_source, ctx.source_path ++ [:groups, group_id, :fields]}

    Enum.reduce(unknown_names, ctx, fn name, ctx ->
      diagnostic = %Diagnostic{
        severity: :warning,
        code: :unknown_group_field,
        message: "group #{inspect(group_id)} references unknown field #{inspect(name)}",
        origin: origin,
        template_path: ctx.template_path
      }

      %{ctx | diagnostics: [diagnostic | ctx.diagnostics]}
    end)
  end
end
