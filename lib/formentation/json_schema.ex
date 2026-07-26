defmodule Formentation.JSONSchema do
  @moduledoc """
  JSON Schema declaration source (D-004): compiles a decoded draft
  2020-12 schema document — string keys, as returned by `JSON.decode!/1`
  — into a definition. The supported keyword subset and the UI-hints
  vocabulary are documented in the slice-2 spec
  (docs/superpowers/specs/2026-07-21-phase1-slice2-json-schema-adapter-design.md)
  and the annotations mini-slice spec
  (docs/superpowers/specs/2026-07-21-phase1-annotations-mini-slice-design.md).
  """

  @behaviour Formentation.Source

  alias Formentation.{
    Definition,
    Diagnostic,
    JSONPointer,
    Node,
    NodeId,
    TemplatePath,
    ValidationPlan
  }

  alias Formentation.JSONSchema.Validator
  alias Formentation.Source.Shared

  @scalar_types %{
    "string" => {:text, :string_default},
    "integer" => {:integer, :integer_default},
    "number" => {:number, :number_default},
    "boolean" => {:boolean, :boolean_default}
  }

  @value_types %{
    "string" => :string,
    "integer" => :integer,
    "number" => :number,
    "boolean" => :boolean
  }

  @constraint_keys %{
    "minLength" => :min_length,
    "maxLength" => :max_length,
    "minimum" => :min,
    "maximum" => :max
  }

  @format_roles %{"date" => :date, "email" => :email, "uri" => :uri}

  @widgets %{
    "textarea" => :textarea,
    "select" => :select,
    "checkbox" => :checkbox,
    "radio" => :radio,
    "text" => :text
  }

  @doc """
  Compiles a decoded schema document. Options: `:ui` — the UI-hints map
  with optional `"fields"`, `"groups"`, and `"order"` keys — plus the
  `:max_depth`/`:max_nodes` budgets shared with the map source.
  """
  @impl true
  def compile(schema, opts \\ []) do
    ui = Keyword.get(opts, :ui, %{})

    with :ok <- check_shape(schema),
         :ok <- check_hints(ui),
         :ok <- check_dialect(schema),
         :ok <- Validator.validate_schema(schema),
         {:ok, definition, _diagnostics} <- walk(schema, opts) do
      definition |> apply_hints(ui) |> with_validation(schema)
    end
  end

  # apply_hints/2 always succeeds (invalid hints are already rejected by
  # check_hints/1 earlier in the `with` chain above), so this has a
  # single clause — a catch-all error clause here is unreachable and
  # trips `--warnings-as-errors`.
  defp with_validation({:ok, definition, diagnostics}, schema) do
    case Validator.build_instance_validator(schema) do
      {:ok, artifact} ->
        plan = %ValidationPlan{module: Validator, artifact: artifact}
        {:ok, %{definition | validation: plan}, diagnostics}

      {:error, message} ->
        diagnostics = diagnostics ++ [validator_unavailable_diagnostic(message)]
        {:ok, %{definition | validation: nil, diagnostics: diagnostics}, diagnostics}
    end
  end

  defp validator_unavailable_diagnostic(message) do
    %Diagnostic{
      severity: :warning,
      code: :validator_unavailable,
      message:
        "instance validation unavailable (#{message}); submitted values are not validated at runtime",
      origin: {:json_schema, ""},
      template_path: %TemplatePath{segments: []}
    }
  end

  defp walk(schema, opts) do
    Shared.compile_impl(schema, opts, &compile_object/3)
  end

  defp check_shape(schema) when is_map(schema), do: :ok

  defp check_shape(other) do
    {:error,
     [
       %Diagnostic{
         severity: :error,
         code: :invalid_schema,
         message: "schema must be a decoded JSON object, got: #{inspect(other)}",
         origin: {:json_schema, ""},
         template_path: %TemplatePath{segments: []}
       }
     ]}
  end

  defp check_dialect(schema) do
    case Map.get(schema, "$schema") do
      nil ->
        :ok

      dialect ->
        if dialect == Validator.dialect() do
          :ok
        else
          {:error,
           [
             %Diagnostic{
               severity: :error,
               code: :unsupported_dialect,
               message:
                 "unsupported dialect #{inspect(dialect)}; supported: #{Validator.dialect()}",
               origin: {:json_schema, "/$schema"},
               template_path: %TemplatePath{segments: []}
             }
           ]}
        end
    end
  end

  defp check_hints(ui) when is_map(ui) do
    order = Map.get(ui, "order", [])
    order_ok? = is_list(order) and Enum.all?(order, &is_binary/1)
    groups = Map.get(ui, "groups", [])
    groups_ok? = is_list(groups) and Enum.all?(groups, &group_hint_ok?/1)
    fields = Map.get(ui, "fields", %{})
    fields_ok? = is_map(fields) and Enum.all?(fields, fn {_name, hint} -> is_map(hint) end)

    if order_ok? and groups_ok? and fields_ok? do
      :ok
    else
      invalid_hints(ui)
    end
  end

  defp check_hints(ui), do: invalid_hints(ui)

  defp group_hint_ok?(%{"id" => id, "fields" => fields, "title" => title})
       when is_binary(id) and is_list(fields) do
    is_binary(title)
  end

  defp group_hint_ok?(%{"id" => id, "fields" => fields}) when is_binary(id) and is_list(fields),
    do: true

  defp group_hint_ok?(_group), do: false

  defp invalid_hints(ui) do
    {:error,
     [
       %Diagnostic{
         severity: :error,
         code: :invalid_ui_hints,
         message: "ui hints do not match the supported vocabulary: #{inspect(ui)}",
         origin: {:ui_hints, ""},
         template_path: %TemplatePath{segments: []}
       }
     ]}
  end

  defp compile_object(%{"type" => "object"} = schema, name, ctx) do
    with :ok <- check_depth(ctx),
         {:ok, ctx} <- take_budget(ctx) do
      required = Map.get(schema, "required", [])
      properties = Map.get(schema, "properties", %{})

      with {:ok, children, ctx} <- compile_properties(properties, required, ctx) do
        children = Shared.stamp_declaration_order(children)
        {label, label_origin} = resolve_label(schema, name, ctx.source_path)
        {help, help_origin} = resolve_help(schema, ctx.source_path)

        node =
          Shared.create_group_node(name, children, ctx,
            label: label,
            label_origin: label_origin,
            help: help,
            help_origin: help_origin
          )

        {:ok, node, ctx}
      end
    end
  end

  defp compile_object(schema, _name, ctx) do
    {:error,
     %Diagnostic{
       severity: :error,
       code: :unsupported_type,
       message: "only object schemas are supported at the root, got: #{inspect(schema)}",
       origin: {:json_schema, JSONPointer.join(ctx.source_path)},
       template_path: ctx.template_path
     }}
  end

  defp check_depth(%Shared.Context{depth: depth, max_depth: max_depth} = ctx)
       when depth > max_depth do
    {:error,
     budget_diagnostic(:max_depth_exceeded, "schema exceeds maximum depth of #{max_depth}", ctx)}
  end

  defp check_depth(_ctx), do: :ok

  defp take_budget(%Shared.Context{nodes_left: nodes_left} = ctx) when nodes_left <= 0 do
    {:error, budget_diagnostic(:max_nodes_exceeded, "schema node budget exhausted", ctx)}
  end

  defp take_budget(%Shared.Context{nodes_left: nodes_left} = ctx) do
    {:ok, %{ctx | nodes_left: nodes_left - 1}}
  end

  defp budget_diagnostic(code, message, ctx) do
    %Diagnostic{
      severity: :error,
      code: code,
      message: message,
      origin: {:json_schema, JSONPointer.join(ctx.source_path)},
      template_path: ctx.template_path
    }
  end

  defp compile_properties(properties, required, ctx) when is_map(properties) do
    properties
    |> Map.keys()
    |> Enum.sort()
    |> Enum.reduce_while({:ok, [], ctx}, fn name, {:ok, acc, ctx} ->
      case compile_property(name, Map.fetch!(properties, name), name in required, ctx) do
        {:ok, node, ctx} -> {:cont, {:ok, [node | acc], ctx}}
        {:error, diagnostic} -> {:halt, {:error, diagnostic}}
      end
    end)
    |> case do
      {:ok, nodes, ctx} -> {:ok, Enum.reverse(nodes), ctx}
      {:error, diagnostic} -> {:error, diagnostic}
    end
  end

  defp compile_property(name, %{"type" => "object"} = schema, required?, ctx) do
    child_ctx = %{
      ctx
      | depth: ctx.depth + 1,
        template_path: TemplatePath.child(ctx.template_path, name),
        source_path: ctx.source_path ++ ["properties", name]
    }

    with {:ok, node, child_ctx} <- compile_object(schema, name, child_ctx) do
      {:ok, %{node | required?: required?},
       %{ctx | diagnostics: child_ctx.diagnostics, nodes_left: child_ctx.nodes_left}}
    end
  end

  defp compile_property(name, %{"type" => "string", "const" => value} = schema, required?, ctx)
       when is_binary(value) do
    compile_scalar(name, schema, required?, ctx)
  end

  defp compile_property(name, %{"type" => "string", "const" => _value} = schema, required?, ctx) do
    unsupported(name, schema, required?, ctx, :unsupported_keyword, "non-string const value")
  end

  defp compile_property(name, %{"const" => _value} = schema, required?, ctx) do
    unsupported(name, schema, required?, ctx, :unsupported_keyword, "const on a non-string type")
  end

  defp compile_property(name, %{"type" => "string", "enum" => enum} = schema, required?, ctx)
       when is_list(enum) do
    if Enum.all?(enum, &is_binary/1) do
      compile_scalar(name, schema, required?, ctx)
    else
      unsupported(name, schema, required?, ctx, :unsupported_keyword, "non-string enum members")
    end
  end

  defp compile_property(name, %{"enum" => enum} = schema, required?, ctx) when is_list(enum) do
    unsupported(name, schema, required?, ctx, :unsupported_keyword, "enum on a non-string type")
  end

  defp compile_property(name, %{"type" => type} = schema, required?, ctx)
       when is_map_key(@scalar_types, type) do
    compile_scalar(name, schema, required?, ctx)
  end

  defp compile_property(name, %{"type" => type} = schema, required?, ctx) do
    unsupported(
      name,
      schema,
      required?,
      ctx,
      :unsupported_type,
      "unsupported type #{inspect(type)}"
    )
  end

  defp compile_property(name, schema, required?, ctx) do
    unsupported(
      name,
      schema,
      required?,
      ctx,
      :unsupported_keyword,
      "no supported type declaration"
    )
  end

  defp compile_scalar(name, schema, required?, ctx) do
    with {:ok, ctx} <- take_budget(ctx) do
      template_path = TemplatePath.child(ctx.template_path, name)
      source_path = ctx.source_path ++ ["properties", name]
      {label, label_origin} = resolve_label(schema, name, source_path)
      {role, role_origin} = resolve_role(schema, source_path)
      {help, help_origin} = resolve_help(schema, source_path)
      {examples, examples_origin} = resolve_examples(schema, source_path)

      {default, default_origin, ctx} =
        resolve_default(schema, name, source_path, template_path, ctx)

      node = %Node.Field{
        id: NodeId.from_path(template_path),
        name: name,
        label: label,
        role: role,
        value_type: Map.fetch!(@value_types, Map.fetch!(schema, "type")),
        help: help,
        template_path: template_path,
        required?: required?,
        options: option_set(schema),
        default: default,
        examples: examples,
        constraints: constraints(schema),
        origins:
          Shared.origin_entries(
            label: label_origin,
            role: role_origin,
            help: help_origin,
            options: options_origin(schema, source_path),
            examples: examples_origin,
            default: default_origin
          )
      }

      {:ok, node, ctx}
    end
  end

  defp unsupported(name, _schema, required?, ctx, code, reason) do
    with {:ok, ctx} <- take_budget(ctx) do
      template_path = TemplatePath.child(ctx.template_path, name)
      source_path = ctx.source_path ++ ["properties", name]

      origin_suffix = if code == :unsupported_type, do: ["type"], else: []
      origin = {:json_schema, JSONPointer.join(source_path ++ origin_suffix)}

      node = %Node.Unsupported{
        id: NodeId.from_path(template_path),
        name: name,
        required?: required?,
        template_path: template_path,
        origins: Shared.origin_entries(kind: origin)
      }

      diagnostic = %Diagnostic{
        severity: :warning,
        code: code,
        message: "#{reason} for property #{inspect(name)}",
        origin: origin,
        template_path: template_path
      }

      {:ok, node, %{ctx | diagnostics: [diagnostic | ctx.diagnostics]}}
    end
  end

  defp resolve_label(%{"title" => title}, _name, source_path) when is_binary(title) do
    {title, {:json_schema, JSONPointer.join(source_path ++ ["title"])}}
  end

  defp resolve_label(_schema, nil, _source_path), do: {nil, nil}

  defp resolve_label(_schema, name, _source_path) do
    {Shared.humanize(name), {:inference, :label_from_name}}
  end

  defp resolve_help(%{"description" => description}, source_path) when is_binary(description) do
    {description, {:json_schema, JSONPointer.join(source_path ++ ["description"])}}
  end

  defp resolve_help(_schema, _source_path), do: {nil, nil}

  defp resolve_examples(schema, source_path) do
    case Map.fetch(schema, "examples") do
      {:ok, examples} ->
        {examples, {:json_schema, JSONPointer.join(source_path ++ ["examples"])}}

      :error ->
        {nil, nil}
    end
  end

  defp resolve_default(schema, name, source_path, template_path, ctx) do
    case Map.fetch(schema, "default") do
      {:ok, nil} ->
        warning = %Diagnostic{
          severity: :warning,
          code: :unsupported_keyword,
          message: "null default for property #{inspect(name)} is ignored",
          origin: {:json_schema, JSONPointer.join(source_path ++ ["default"])},
          template_path: template_path
        }

        {nil, nil, %{ctx | diagnostics: [warning | ctx.diagnostics]}}

      {:ok, value} ->
        {value, {:json_schema, JSONPointer.join(source_path ++ ["default"])}, ctx}

      :error ->
        {nil, nil, ctx}
    end
  end

  defp resolve_role(%{"format" => format}, source_path) when is_map_key(@format_roles, format) do
    {Map.fetch!(@format_roles, format),
     {:json_schema, JSONPointer.join(source_path ++ ["format"])}}
  end

  defp resolve_role(%{"const" => _value}, _source_path) do
    {:select, {:inference, :const_select}}
  end

  defp resolve_role(%{"enum" => enum}, _source_path) when is_list(enum) do
    {:select, {:inference, :enum_select}}
  end

  defp resolve_role(%{"type" => type}, _source_path) do
    {role, rule} = Map.fetch!(@scalar_types, type)
    {role, {:inference, rule}}
  end

  defp constraints(schema) do
    for {keyword, key} <- @constraint_keys, Map.has_key?(schema, keyword), into: %{} do
      {key, Map.fetch!(schema, keyword)}
    end
  end

  defp option_set(%{"const" => value}), do: [value]
  defp option_set(%{"enum" => enum}) when is_list(enum), do: enum
  defp option_set(_schema), do: nil

  defp options_origin(%{"const" => _value}, source_path) do
    {:json_schema, JSONPointer.join(source_path ++ ["const"])}
  end

  defp options_origin(%{"enum" => enum}, source_path) when is_list(enum) do
    {:json_schema, JSONPointer.join(source_path ++ ["enum"])}
  end

  defp options_origin(_schema, _source_path), do: nil

  defp apply_hints(%Definition{root: root} = definition, ui) do
    {children, field_warnings} =
      apply_field_hints(root.children, Map.get(ui, "fields", %{}))

    {children, group_warnings} =
      apply_group_hints(children, Map.get(ui, "groups", []))

    {children, order_warnings} = apply_order(children, Map.get(ui, "order"))

    diagnostics = definition.diagnostics ++ field_warnings ++ group_warnings ++ order_warnings
    definition = %{definition | root: %{root | children: children}, diagnostics: diagnostics}
    {:ok, definition, diagnostics}
  end

  defp apply_field_hints(children, fields) do
    {by_name, warnings} =
      Enum.reduce(fields, {Map.new(children, &{&1.name, &1}), []}, fn {name, hint},
                                                                      {by_name, warnings} ->
        case by_name do
          %{^name => %Node.Field{} = node} ->
            {node, new_warnings} = apply_field_hint(node, name, hint)
            {%{by_name | name => node}, [new_warnings | warnings]}

          %{^name => _non_field} ->
            {by_name, warnings}

          _no_match ->
            {by_name, [[unknown_hint_field(name)] | warnings]}
        end
      end)

    {Enum.map(children, &Map.fetch!(by_name, &1.name)), flatten_warnings(warnings)}
  end

  defp flatten_warnings(warnings), do: warnings |> Enum.reverse() |> List.flatten()

  defp apply_field_hint(node, name, hint) do
    {node, widget_warnings} = apply_widget(node, name, hint)
    node = apply_help(node, name, hint)
    {node, hidden_warnings} = apply_hidden(node, name, hint)
    {node, read_only_warnings} = apply_read_only(node, name, hint)
    {node, widget_warnings ++ hidden_warnings ++ read_only_warnings}
  end

  defp apply_widget(node, name, %{"widget" => widget}) when is_map_key(@widgets, widget) do
    pointer = JSONPointer.join(["fields", name, "widget"])

    {%{
       node
       | widget: Map.fetch!(@widgets, widget),
         origins: node.origins ++ [widget: {:ui_hints, pointer}]
     }, []}
  end

  defp apply_widget(node, name, %{"widget" => widget}) do
    warning = %Diagnostic{
      severity: :warning,
      code: :unknown_widget,
      message: "unknown widget #{inspect(widget)} for field #{inspect(name)}",
      origin: {:ui_hints, JSONPointer.join(["fields", name, "widget"])},
      template_path: %TemplatePath{segments: []}
    }

    {node, [warning]}
  end

  defp apply_widget(node, _name, _hint), do: {node, []}

  defp apply_help(node, name, %{"help" => help}) when is_binary(help) do
    pointer = JSONPointer.join(["fields", name, "help"])
    origins = Keyword.delete(node.origins, :help) ++ [help: {:ui_hints, pointer}]
    %{node | help: help, origins: origins}
  end

  defp apply_help(node, _name, _hint), do: node

  defp apply_hidden(node, name, %{"hidden" => value}) when is_boolean(value) do
    pointer = JSONPointer.join(["fields", name, "hidden"])
    {%{node | hidden?: value, origins: node.origins ++ [hidden: {:ui_hints, pointer}]}, []}
  end

  defp apply_hidden(node, name, %{"hidden" => other}) do
    {node, [invalid_flag_warning("hidden", name, other)]}
  end

  defp apply_hidden(node, _name, _hint), do: {node, []}

  defp apply_read_only(node, name, %{"read_only" => value}) when is_boolean(value) do
    pointer = JSONPointer.join(["fields", name, "read_only"])

    {%{node | read_only?: value, origins: node.origins ++ [read_only: {:ui_hints, pointer}]}, []}
  end

  defp apply_read_only(node, name, %{"read_only" => other}) do
    {node, [invalid_flag_warning("read_only", name, other)]}
  end

  defp apply_read_only(node, _name, _hint), do: {node, []}

  defp invalid_flag_warning(key, name, value) do
    %Diagnostic{
      severity: :warning,
      code: :invalid_hint_value,
      message:
        "#{key} for field #{inspect(name)} must be a boolean, " <>
          "got: #{inspect(value)}; ignored",
      origin: {:ui_hints, JSONPointer.join(["fields", name, key])},
      template_path: %TemplatePath{segments: []}
    }
  end

  defp unknown_hint_field(name) do
    %Diagnostic{
      severity: :warning,
      code: :unknown_hint_field,
      message: "ui hints reference unknown field #{inspect(name)}",
      origin: {:ui_hints, JSONPointer.join(["fields", name])},
      template_path: %TemplatePath{segments: []}
    }
  end

  defp apply_group_hints(children, groups) do
    {children, warnings, _count} =
      Enum.reduce(groups, {children, [], 0}, fn group, {children, warnings, index} ->
        spec = %{
          id: Map.fetch!(group, "id"),
          label: group["title"],
          label_origin: group_label_origin(group, index),
          fields: Map.fetch!(group, "fields")
        }

        {children, unknown} = Shared.attach_group(children, spec, %TemplatePath{segments: []})
        new_warnings = Enum.map(unknown, &unknown_group_field(&1, group, index))
        {children, [new_warnings | warnings], index + 1}
      end)

    {children, flatten_warnings(warnings)}
  end

  defp group_label_origin(%{"title" => title}, index) when is_binary(title) do
    {:ui_hints, "/groups/#{index}/title"}
  end

  defp group_label_origin(_group, _index), do: nil

  defp unknown_group_field(name, group, index) do
    %Diagnostic{
      severity: :warning,
      code: :unknown_group_field,
      message: "group #{inspect(group["id"])} references unknown field #{inspect(name)}",
      origin: {:ui_hints, "/groups/#{index}/fields"},
      template_path: %TemplatePath{segments: []}
    }
  end

  defp apply_order(children, nil), do: {children, []}

  defp apply_order(children, order) when is_list(order) do
    {matched, warnings} =
      Enum.reduce(order, {[], []}, fn entry, {matched, warnings} ->
        case Enum.find(children, &order_match?(&1, entry)) do
          nil -> {matched, [unknown_order_entry(entry) | warnings]}
          child -> {[child | matched], warnings}
        end
      end)

    matched = matched |> Enum.reverse() |> Enum.uniq()
    {matched ++ Enum.reject(children, &(&1 in matched)), Enum.reverse(warnings)}
  end

  defp order_match?(child, entry) do
    child.name == entry or child.id == NodeId.group(%TemplatePath{segments: []}, entry)
  end

  defp unknown_order_entry(entry) do
    %Diagnostic{
      severity: :warning,
      code: :unknown_order_entry,
      message: "order references unknown field or group #{inspect(entry)}",
      origin: {:ui_hints, "/order"},
      template_path: %TemplatePath{segments: []}
    }
  end
end
