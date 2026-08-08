defmodule Formentation.Definition.Source.JSONSchema do
  @moduledoc """
  JSON Schema declaration source (D-004): compiles a decoded draft
  2020-12 schema document — string keys, as returned by `JSON.decode!/1`
  — into a definition. The supported keyword subset and the UI-hints
  vocabulary are documented in the slice-2 spec
  (docs/superpowers/specs/2026-07-21-phase1-slice2-json-schema-adapter-design.md)
  and the annotations mini-slice spec
  (docs/superpowers/specs/2026-07-21-phase1-annotations-mini-slice-design.md).
  """

  @behaviour Formentation.Definition.Source

  alias Formentation.{
    Definition,
    Diagnostic,
    JSONPointer,
    NodeId,
    TemplatePath
  }

  alias Formentation.Definition.{Finalizer, Presentation, Semantic, ValidationPlan}
  alias Formentation.Definition.Source.JSONSchema.Validator
  alias Formentation.Definition.Source.Shared

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
    Shared.compile_compiled_impl(schema, opts, &compile_object/3)
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
        {label, label_origin} = resolve_label(schema, name, ctx.source_path)
        {help, help_origin} = resolve_help(schema, ctx.source_path)

        presentation_origins = Shared.origin_entries(label: label_origin, help: help_origin)

        semantic = Semantic.Object.new(name, ctx.template_path, Enum.map(children, & &1.semantic))

        presentation =
          Presentation.Object.new(
            semantic.id,
            children |> Enum.map(& &1.presentation) |> Enum.reject(&is_nil/1),
            label: label,
            help: help,
            origins: presentation_origins
          )

        {:ok,
         %Shared.Compiled{
           semantic: semantic,
           presentation: presentation
         }, ctx}
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
        {:ok, %Shared.Compiled{} = compiled, ctx} -> {:cont, {:ok, [compiled | acc], ctx}}
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

    with {:ok, %Shared.Compiled{} = compiled, child_ctx} <-
           compile_object(schema, name, child_ctx) do
      Shared.require_compiled_object(compiled, child_ctx, ctx, required?)
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

      origins =
        Shared.origin_entries(
          label: label_origin,
          role: role_origin,
          help: help_origin,
          options: options_origin(schema, source_path),
          examples: examples_origin,
          default: default_origin
        )

      semantic =
        Semantic.Field.new(
          name,
          template_path,
          Map.fetch!(@value_types, Map.fetch!(schema, "type")),
          role: role,
          required?: required?,
          options: option_set(schema),
          default: default,
          examples: examples,
          constraints: constraints(schema),
          origins: semantic_origins(origins)
        )

      presentation =
        Presentation.Field.new(semantic.id,
          label: label,
          help: help,
          origins: presentation_origins(origins)
        )

      {:ok, %Shared.Compiled{semantic: semantic, presentation: presentation}, ctx}
    end
  end

  defp unsupported(name, _schema, required?, ctx, code, reason) do
    with {:ok, ctx} <- take_budget(ctx) do
      template_path = TemplatePath.child(ctx.template_path, name)
      source_path = ctx.source_path ++ ["properties", name]

      origin_suffix = if code == :unsupported_type, do: ["type"], else: []
      origin = {:json_schema, JSONPointer.join(source_path ++ origin_suffix)}

      origins = Shared.origin_entries(kind: origin)

      semantic =
        Semantic.Unsupported.new(name, template_path,
          required?: required?,
          origins: origins
        )

      diagnostic = %Diagnostic{
        severity: :warning,
        code: code,
        message: "#{reason} for property #{inspect(name)}",
        origin: origin,
        template_path: template_path
      }

      {:ok, %Shared.Compiled{semantic: semantic, presentation: nil},
       %{ctx | diagnostics: [diagnostic | ctx.diagnostics]}}
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

  @semantic_origin_keys [:role, :options, :examples, :default, :read_only]
  @presentation_origin_keys [:label, :help, :widget, :hidden]

  defp semantic_origins(origins), do: Shared.fact_origins(origins, @semantic_origin_keys)
  defp presentation_origins(origins), do: Shared.fact_origins(origins, @presentation_origin_keys)

  defp apply_hints(
         %Definition{semantic: semantic, presentation: presentation} = definition,
         ui
       ) do
    fields = Map.get(ui, "fields", %{})
    {semantic, field_warnings} = apply_native_semantic_field_hints(semantic, fields)

    presentation =
      presentation
      |> apply_native_presentation_field_hints(fields, semantic)

    {presentation, group_warnings} =
      apply_native_group_hints(presentation, Map.get(ui, "groups", []), semantic)

    {presentation, order_warnings} =
      apply_native_order(presentation, Map.get(ui, "order"), semantic)

    diagnostics = definition.diagnostics ++ field_warnings ++ group_warnings ++ order_warnings

    {:ok, native_definition} =
      Finalizer.finalize(semantic, presentation, diagnostics: diagnostics)

    definition = %{
      definition
      | semantic: native_definition.semantic,
        semantic_index: native_definition.semantic_index,
        presentation: native_definition.presentation,
        diagnostics: diagnostics
    }

    {:ok, definition, diagnostics}
  end

  defp flatten_warnings(warnings), do: warnings |> Enum.reverse() |> List.flatten()

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

  defp unknown_order_entry(entry) do
    %Diagnostic{
      severity: :warning,
      code: :unknown_order_entry,
      message: "order references unknown field or group #{inspect(entry)}",
      origin: {:ui_hints, "/order"},
      template_path: %TemplatePath{segments: []}
    }
  end

  defp apply_native_semantic_field_hints(%Semantic.Object{} = semantic, fields) do
    field_kind_by_name = Map.new(semantic.children, &{&1.name, semantic_kind(&1)})
    warnings = field_hint_warnings(fields, field_kind_by_name)

    children =
      Enum.map(semantic.children, fn
        %Semantic.Field{name: name} = field ->
          case Map.get(fields, name) do
            %{"read_only" => value} when is_boolean(value) ->
              pointer = JSONPointer.join(["fields", name, "read_only"])

              %{
                field
                | read_only?: value,
                  origins: field.origins ++ [read_only: {:ui_hints, pointer}]
              }

            _hint_or_missing ->
              field
          end

        child ->
          child
      end)

    {%{semantic | children: children}, warnings}
  end

  defp semantic_kind(%Semantic.Field{}), do: :field
  defp semantic_kind(%Semantic.Object{}), do: :object
  defp semantic_kind(%Semantic.Unsupported{}), do: :unsupported

  defp field_hint_warnings(fields, field_kind_by_name) do
    fields
    |> Enum.flat_map(fn {name, hint} ->
      case Map.get(field_kind_by_name, name) do
        :field -> invalid_field_hint_warnings(name, hint)
        nil -> [unknown_hint_field(name)]
        _non_field -> []
      end
    end)
  end

  defp invalid_field_hint_warnings(name, hint) do
    []
    |> maybe_unknown_widget(name, hint)
    |> maybe_invalid_flag("hidden", name, hint)
    |> maybe_invalid_flag("read_only", name, hint)
    |> Enum.reverse()
  end

  defp maybe_unknown_widget(warnings, name, %{"widget" => widget})
       when not is_map_key(@widgets, widget) do
    [
      %Diagnostic{
        severity: :warning,
        code: :unknown_widget,
        message: "unknown widget #{inspect(widget)} for field #{inspect(name)}",
        origin: {:ui_hints, JSONPointer.join(["fields", name, "widget"])},
        template_path: %TemplatePath{segments: []}
      }
      | warnings
    ]
  end

  defp maybe_unknown_widget(warnings, _name, _hint), do: warnings

  defp maybe_invalid_flag(warnings, key, name, hint) do
    case Map.fetch(hint, key) do
      {:ok, value} when is_boolean(value) -> warnings
      {:ok, value} -> [invalid_flag_warning(key, name, value) | warnings]
      :error -> warnings
    end
  end

  defp apply_native_presentation_field_hints(
         %Presentation.Object{} = presentation,
         fields,
         semantic
       ) do
    field_ids_by_name =
      semantic.children
      |> Enum.filter(&match?(%Semantic.Field{}, &1))
      |> Map.new(&{&1.name, &1.id})

    children =
      Enum.map(presentation.children, fn
        %Presentation.Field{semantic_id: semantic_id} = field ->
          apply_native_presentation_field_hint(field, semantic_id, field_ids_by_name, fields)

        child ->
          child
      end)

    %{presentation | children: children}
  end

  defp apply_native_presentation_field_hint(field, semantic_id, field_ids_by_name, fields) do
    case Enum.find(field_ids_by_name, fn {_name, id} -> id == semantic_id end) do
      {name, ^semantic_id} -> maybe_apply_native_presentation_field_hint(field, name, fields)
      nil -> field
    end
  end

  defp maybe_apply_native_presentation_field_hint(field, name, fields) do
    case Map.get(fields, name) do
      hint when is_map(hint) -> apply_native_presentation_field_hint(field, name, hint)
      _missing_or_non_field -> field
    end
  end

  defp apply_native_presentation_field_hint(field, name, hint) do
    field
    |> apply_native_widget(name, hint)
    |> apply_native_help(name, hint)
    |> apply_native_hidden(name, hint)
  end

  defp apply_native_widget(field, name, %{"widget" => widget})
       when is_map_key(@widgets, widget) do
    pointer = JSONPointer.join(["fields", name, "widget"])

    %{
      field
      | widget: Map.fetch!(@widgets, widget),
        origins: field.origins ++ [widget: {:ui_hints, pointer}]
    }
  end

  defp apply_native_widget(field, _name, _hint), do: field

  defp apply_native_help(field, name, %{"help" => help}) when is_binary(help) do
    pointer = JSONPointer.join(["fields", name, "help"])
    origins = Keyword.delete(field.origins, :help) ++ [help: {:ui_hints, pointer}]
    %{field | help: help, origins: origins}
  end

  defp apply_native_help(field, _name, _hint), do: field

  defp apply_native_hidden(field, name, %{"hidden" => value}) when is_boolean(value) do
    pointer = JSONPointer.join(["fields", name, "hidden"])
    %{field | hidden?: value, origins: field.origins ++ [hidden: {:ui_hints, pointer}]}
  end

  defp apply_native_hidden(field, _name, _hint), do: field

  defp apply_native_group_hints(%Presentation.Object{} = presentation, groups, semantic) do
    {children, warnings, _index} =
      Enum.reduce(groups, {presentation.children, [], 0}, fn group, {children, warnings, index} ->
        spec = %Shared.PresentationGroupSpec{
          id: Map.fetch!(group, "id"),
          label: group["title"],
          label_origin: group_label_origin(group, index),
          fields: Map.fetch!(group, "fields")
        }

        {children, unknown} = attach_native_group(children, semantic, spec)
        new_warnings = Enum.map(unknown, &unknown_group_field(&1, group, index))
        {children, [new_warnings | warnings], index + 1}
      end)

    {%{presentation | children: children}, flatten_warnings(warnings)}
  end

  defp attach_native_group(
         children,
         semantic,
         %Shared.PresentationGroupSpec{fields: fields} = spec
       ) do
    fields = Enum.uniq(fields)
    by_name = Shared.presentation_children_by_name(children, semantic.children)
    unsupported_names = Shared.unsupported_names(semantic.children)

    members =
      fields
      |> Enum.filter(&is_map_key(by_name, &1))
      |> Enum.map(&Map.fetch!(by_name, &1))

    unknown =
      Enum.reject(fields, &(is_map_key(by_name, &1) or MapSet.member?(unsupported_names, &1)))

    {place_native_group(children, spec, members), unknown}
  end

  defp place_native_group(children, _spec, []), do: children

  defp place_native_group(children, %Shared.PresentationGroupSpec{id: id} = spec, members) do
    group =
      Presentation.Group.new(NodeId.group(%TemplatePath{segments: []}, id), members,
        label: spec.label,
        origins: Shared.origin_entries(label: spec.label_origin)
      )

    member_ids = MapSet.new(members, & &1.semantic_id)
    first_index = Enum.find_index(children, &(Shared.presentation_reference_id(&1) in member_ids))

    children
    |> Enum.reject(&(Shared.presentation_reference_id(&1) in member_ids))
    |> List.insert_at(first_index, group)
  end

  defp apply_native_order(%Presentation.Object{} = presentation, nil, _semantic),
    do: {presentation, []}

  defp apply_native_order(%Presentation.Object{} = presentation, order, semantic)
       when is_list(order) do
    name_by_id = Map.new(semantic.children, &{&1.id, &1.name})

    {matched, warnings} =
      Enum.reduce(order, {[], []}, fn entry, {matched, unknown} ->
        case Enum.find(presentation.children, &native_order_match?(&1, entry, name_by_id)) do
          nil -> {matched, [unknown_order_entry(entry) | unknown]}
          child -> {[child | matched], unknown}
        end
      end)

    matched = matched |> Enum.reverse() |> Enum.uniq()

    {%{presentation | children: matched ++ Enum.reject(presentation.children, &(&1 in matched))},
     Enum.reverse(warnings)}
  end

  defp native_order_match?(%Presentation.Group{id: id}, entry, _name_by_id),
    do: id == NodeId.group(%TemplatePath{segments: []}, entry)

  defp native_order_match?(child, entry, name_by_id) do
    Map.get(name_by_id, Shared.presentation_reference_id(child)) == entry
  end
end
