defmodule Formentation.Source.Map do
  @moduledoc """
  Plain Elixir data declaration source — the reference adapter and
  cheapest fixture format (D-004). Lives in core with zero dependencies.

  A declaration is a map with a `:kind`. Object properties are an ordered
  list of `{name, spec}` tuples, so ordering is data, never map
  enumeration order.
  """

  @behaviour Formentation.Source

  alias Formentation.{Diagnostic, Node, NodeId, TemplatePath}
  alias Formentation.Source.Shared

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
    Shared.compile_impl(declaration, opts, &compile_object/3)
  end

  defp compile_object(%{kind: :object} = declaration, name, ctx) do
    with :ok <- check_depth(ctx),
         {:ok, ctx} <- take_budget(ctx),
         {:ok, required} <- fetch_list(declaration, :required, ctx),
         {:ok, children, ctx} <- compile_children(declaration, required, ctx),
         {:ok, groups} <- fetch_groups(declaration, ctx) do
      children = Shared.stamp_declaration_order(children)
      {children, ctx} = attach_groups(children, groups, ctx)
      {label, label_origin} = resolve_label(declaration, name, ctx.source_path)

      node =
        Shared.create_group_node(name, children, ctx,
          label: label,
          label_origin: label_origin,
          help: declaration[:help],
          help_origin: key_origin(declaration, :help, ctx.source_path)
        )

      {:ok, node, ctx}
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
    properties
    |> Enum.reduce_while({:ok, [], ctx}, fn {prop_name, spec}, {:ok, acc, ctx} ->
      case compile_property(prop_name, spec, prop_name in required, ctx) do
        {:ok, node, ctx} -> {:cont, {:ok, [node | acc], ctx}}
        {:error, diagnostic} -> {:halt, {:error, diagnostic}}
      end
    end)
    |> case do
      {:ok, nodes, ctx} -> {:ok, Enum.reverse(nodes), ctx}
      {:error, diagnostic} -> {:error, diagnostic}
    end
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

    with {:ok, node, child_ctx} <- compile_object(spec, name, child_ctx) do
      {:ok, %{node | required?: required?},
       %{ctx | diagnostics: child_ctx.diagnostics, nodes_left: child_ctx.nodes_left}}
    end
  end

  defp compile_property(name, %{kind: kind} = spec, required?, ctx) when kind in @scalar_kinds do
    compile_field(name, spec, required?, ctx)
  end

  defp compile_property(name, %{kind: kind}, required?, ctx) do
    with {:ok, ctx} <- take_budget(ctx) do
      template_path = TemplatePath.child(ctx.template_path, name)
      source_path = ctx.source_path ++ [:properties, name]

      node = %Node.Unsupported{
        id: NodeId.from_path(template_path),
        name: name,
        required?: required?,
        template_path: template_path,
        origins: Shared.origin_entries(kind: {:map_source, source_path ++ [:kind]})
      }

      diagnostic = %Diagnostic{
        severity: :warning,
        code: :unsupported_kind,
        message: "unsupported kind #{inspect(kind)} for property #{inspect(name)}",
        origin: {:map_source, source_path ++ [:kind]},
        template_path: template_path
      }

      {:ok, node, %{ctx | diagnostics: [diagnostic | ctx.diagnostics]}}
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

      node = %Node.Field{
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
        origins:
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
      }

      {:ok, node, ctx}
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
