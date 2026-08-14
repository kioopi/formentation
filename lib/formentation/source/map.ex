defmodule Formentation.Source.Map do
  @moduledoc """
  Plain Elixir data declaration source — the reference adapter and
  cheapest fixture format (D-004). Lives in core with zero dependencies.

  A declaration is a map with a `:kind`. Object properties are an ordered
  list of `{name, spec}` tuples, so ordering is data, never map
  enumeration order.

  Field specifications support `:one_of` options lists containing scalar values
  (`String.t()`, `number()`, or `boolean()`). Unsupported non-scalar values in
  `:one_of` produce an `:invalid_declaration` error.

  Selected as `adapter: :map`. The declaration vocabulary this module
  compiles is the supported surface; the compiled `Formentation.Definition`
  it produces is queried through `Formentation.Info` rather than
  pattern-matched. See `Formentation.Source` for the adapter
  compatibility boundary.
  """

  @behaviour Formentation.Source

  alias Formentation.Definition.{Presentation, Semantic}
  alias Formentation.{Diagnostic, NodeId, TemplatePath}
  alias Formentation.Source.Shared

  @behaviour Shared.Dialect

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
  @impl Formentation.Source
  def compile(declaration, opts \\ []) do
    with {:ok, build} <- Shared.walk(declaration, __MODULE__, opts, &compile_object/3) do
      Shared.finalize(build)
    end
  end

  @doc false
  @impl Shared.Dialect
  def noun, do: "declaration"

  @doc false
  @impl Shared.Dialect
  def origin(source_path), do: {:map_source, source_path}

  @doc false
  @impl Shared.Dialect
  def property_segment(name), do: [:properties, name]

  @doc false
  @impl Shared.Dialect
  def item_segment, do: [:item]

  defp compile_object(%{kind: :object} = declaration, name, ctx) do
    with :ok <- Shared.Context.check_depth(ctx),
         {:ok, ctx} <- Shared.Context.take_budget(ctx),
         {:ok, children, ctx} <- compile_children(declaration, ctx),
         {:ok, groups} <- fetch_groups(declaration, ctx),
         {:ok, {label, label_origin}} <-
           resolve_label(declaration, name, ctx.source_path, ctx.template_path, ctx),
         {:ok, help} <-
           fetch_optional_string(
             declaration,
             :help,
             subject(name, ctx.template_path),
             ctx.source_path,
             ctx.template_path,
             ctx
           ) do
      semantic_children = Enum.map(children, & &1.semantic)
      {presentation_children, ctx} = attach_presentation_groups(children, groups, ctx)

      presentation_origins =
        Shared.origin_entries(
          label: label_origin,
          help: key_origin(declaration, :help, ctx.source_path)
        )

      semantic = Semantic.Object.new(name, ctx.template_path, semantic_children)

      presentation =
        Presentation.Object.new(semantic.id, presentation_children,
          label: label,
          help: help,
          origins: presentation_origins
        )

      {:ok, %Shared.Compiled{semantic: semantic, presentation: presentation}, ctx}
    end
  end

  defp compile_object(declaration, _name, ctx) do
    {:error, invalid("expected an object declaration, got: #{inspect(declaration)}", ctx)}
  end

  defp compile_children(declaration, ctx) do
    with {:ok, properties} <- fetch_list(declaration, :properties, ctx),
         {:ok, properties} <- validate_property_entries(properties, ctx),
         :ok <- reject_duplicate_properties(properties, ctx) do
      compile_properties(properties, declaration, ctx)
    end
  end

  defp compile_properties(properties, declaration, ctx) do
    with {:ok, required} <- fetch_required(declaration, property_names(properties), ctx),
         {:ok, compiled, ctx} <- compile_properties_in_order(properties, required, ctx) do
      {:ok, Enum.reverse(compiled), ctx}
    end
  end

  defp fetch_required(declaration, property_names, ctx) do
    with {:ok, required} <- fetch_list(declaration, :required, ctx) do
      validate_required_members(required, property_names, ctx)
    end
  end

  defp validate_required_members(required, property_names, ctx) do
    required
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, MapSet.new()}, fn {name, index}, {:ok, acc} ->
      case validate_required_member(name, index, property_names, ctx) do
        :ok -> {:cont, {:ok, MapSet.put(acc, name)}}
        {:error, diagnostic} -> {:halt, {:error, diagnostic}}
      end
    end)
  end

  defp validate_required_member(name, index, _property_names, ctx) when not is_binary(name) do
    {:error,
     invalid(
       "required entry #{index}: expected a string, got: #{inspect(name)}",
       ctx,
       ctx.source_path ++ [:required, index]
     )}
  end

  defp validate_required_member(name, index, property_names, ctx) do
    if MapSet.member?(property_names, name) do
      :ok
    else
      {:error,
       invalid(
         "required entry #{index}: #{inspect(name)} is not a declared property",
         ctx,
         ctx.source_path ++ [:required, index]
       )}
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

  defp validate_property_entries(properties, ctx) do
    properties
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {entry, index}, {:ok, acc} ->
      case validate_property_entry(entry, index, ctx) do
        {:ok, valid_entry} -> {:cont, {:ok, [valid_entry | acc]}}
        {:error, diagnostic} -> {:halt, {:error, diagnostic}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      {:error, diagnostic} -> {:error, diagnostic}
    end
  end

  defp validate_property_entry({name, spec}, _index, _ctx)
       when is_binary(name) and is_map(spec) do
    {:ok, {name, spec}}
  end

  defp validate_property_entry({name, _spec}, index, ctx) when not is_binary(name) do
    {:error,
     invalid(
       "properties entry #{index}: name must be a string, got: #{inspect(name)}",
       ctx,
       ctx.source_path ++ [:properties, index]
     )}
  end

  defp validate_property_entry({name, spec}, _index, ctx) when is_binary(name) do
    {:error,
     invalid(
       "property #{inspect(name)}: spec must be a map, got: #{inspect(spec)}",
       ctx,
       ctx.source_path ++ [:properties, name]
     )}
  end

  defp validate_property_entry(other, index, ctx) do
    {:error,
     invalid(
       "properties entry #{index}: expected a {name, spec} tuple, got: #{inspect(other)}",
       ctx,
       ctx.source_path ++ [:properties, index]
     )}
  end

  defp property_names(properties) do
    properties |> Enum.map(fn {name, _spec} -> name end) |> MapSet.new()
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
        {:error,
         invalid(
           "#{key}: expected a list, got: #{inspect(other)}",
           ctx,
           ctx.source_path ++ [key]
         )}
    end
  end

  defp fetch_groups(declaration, ctx) do
    with {:ok, groups} <- fetch_list(declaration, :groups, ctx) do
      validate_groups(groups, ctx)
    end
  end

  defp validate_groups(groups, ctx) do
    groups
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], MapSet.new()}, fn {group, index}, {:ok, acc, seen_ids} ->
      case validate_group(group, index, seen_ids, ctx) do
        {:ok, id} -> {:cont, {:ok, [group | acc], MapSet.put(seen_ids, id)}}
        {:error, diagnostic} -> {:halt, {:error, diagnostic}}
      end
    end)
    |> case do
      {:ok, acc, _seen_ids} -> {:ok, Enum.reverse(acc)}
      {:error, diagnostic} -> {:error, diagnostic}
    end
  end

  defp validate_group(%{id: id, fields: fields} = group, index, seen_ids, ctx) do
    with :ok <- validate_group_id(id, index, seen_ids, ctx),
         :ok <- validate_group_fields(fields, index, ctx),
         :ok <- validate_group_title(Map.get(group, :title), index, ctx) do
      {:ok, id}
    end
  end

  defp validate_group(other, index, _seen_ids, ctx) do
    {:error,
     invalid(
       "group #{index}: missing :id or :fields: #{inspect(other)}",
       ctx,
       ctx.source_path ++ [:groups, index]
     )}
  end

  defp validate_group_id(id, index, _seen_ids, ctx) when not is_binary(id) do
    {:error,
     invalid(
       "group #{index}: :id must be a string, got: #{inspect(id)}",
       ctx,
       ctx.source_path ++ [:groups, index, :id]
     )}
  end

  defp validate_group_id(id, index, seen_ids, ctx) do
    if MapSet.member?(seen_ids, id) do
      {:error,
       invalid(
         "group #{index}: duplicate group id #{inspect(id)}",
         ctx,
         ctx.source_path ++ [:groups, index, :id]
       )}
    else
      :ok
    end
  end

  defp validate_group_fields(fields, index, ctx) when not is_list(fields) do
    {:error,
     invalid(
       "group #{index}: :fields must be a list, got: #{inspect(fields)}",
       ctx,
       ctx.source_path ++ [:groups, index, :fields]
     )}
  end

  defp validate_group_fields(fields, index, ctx) do
    case Enum.find(Enum.with_index(fields), fn {name, _field_index} -> not is_binary(name) end) do
      nil ->
        :ok

      {name, field_index} ->
        {:error,
         invalid(
           "group #{index}: field #{field_index} must be a string, got: #{inspect(name)}",
           ctx,
           ctx.source_path ++ [:groups, index, :fields, field_index]
         )}
    end
  end

  defp validate_group_title(nil, _index, _ctx), do: :ok
  defp validate_group_title(title, _index, _ctx) when is_binary(title), do: :ok

  defp validate_group_title(title, index, ctx) do
    {:error,
     invalid(
       "group #{index}: :title must be a string, got: #{inspect(title)}",
       ctx,
       ctx.source_path ++ [:groups, index, :title]
     )}
  end

  defp compile_property(name, %{kind: :object} = spec, required?, ctx) do
    child_ctx = Shared.Context.enter_property(ctx, name)

    with {:ok, %Shared.Compiled{} = compiled, child_ctx} <- compile_object(spec, name, child_ctx) do
      Shared.require_compiled_object(compiled, child_ctx, ctx, required?)
    end
  end

  defp compile_property(name, %{kind: kind} = spec, required?, ctx) when kind in @scalar_kinds do
    compile_field(name, spec, required?, ctx)
  end

  # Nested collections are legal in the recursive semantic model but
  # deferred by compilation in Milestone B (D-053): any array declared
  # below an :item segment degrades to a preserve-only Unsupported node.
  defp compile_property(name, %{kind: :collection} = spec, required?, ctx) do
    if below_item?(ctx) do
      nested_collection_unsupported(name, required?, ctx)
    else
      compile_collection(name, spec, required?, ctx)
    end
  end

  defp compile_property(name, %{kind: kind}, required?, ctx) when is_atom(kind) do
    with {:ok, ctx} <- Shared.Context.take_budget(ctx) do
      template_path = TemplatePath.child(ctx.template_path, name)
      source_path = ctx.source_path ++ [:properties, name]

      origins = Shared.origin_entries(kind: {:map_source, source_path ++ [:kind]})

      semantic =
        Semantic.Unsupported.new(name, template_path,
          required?: required?,
          origins: origins
        )

      diagnostic = %Diagnostic{
        severity: :warning,
        code: :unsupported_kind,
        message: "unsupported kind #{inspect(kind)} for property #{inspect(name)}",
        origin: {:map_source, source_path ++ [:kind]},
        template_path: template_path
      }

      {:ok, %Shared.Compiled{semantic: semantic, presentation: nil},
       Shared.Context.add_diagnostic(ctx, diagnostic)}
    end
  end

  defp compile_property(name, %{kind: kind}, _required?, ctx) do
    {:error,
     invalid(
       "property #{inspect(name)} kind must be an atom, got: #{inspect(kind)}",
       ctx,
       ctx.source_path ++ [:properties, name, :kind],
       TemplatePath.child(ctx.template_path, name)
     )}
  end

  defp compile_property(name, spec, _required?, ctx) do
    {:error,
     invalid(
       "property #{inspect(name)} has no kind: #{inspect(spec)}",
       ctx,
       ctx.source_path ++ [:properties, name, :kind],
       TemplatePath.child(ctx.template_path, name)
     )}
  end

  defp below_item?(%Shared.Context{template_path: %TemplatePath{segments: segments}}),
    do: :item in segments

  defp compile_collection(name, spec, required?, ctx) do
    template_path = TemplatePath.child(ctx.template_path, name)
    source_path = ctx.source_path ++ [:properties, name]

    with {:ok, ctx} <- Shared.Context.take_budget(ctx),
         {:ok, constraints} <-
           validate_collection_constraints(spec, name, source_path, template_path, ctx),
         {:ok, item_spec} <- fetch_item_spec(spec, name, source_path, template_path, ctx),
         {:ok, {label, label_origin}} <-
           resolve_label(spec, name, source_path, template_path, ctx),
         {:ok, help} <-
           fetch_optional_string(
             spec,
             :help,
             subject(name, template_path),
             source_path,
             template_path,
             ctx
           ),
         {:ok, item_spec, ctx} <-
           resolve_item_required(item_spec, name, source_path, template_path, ctx),
         {:ok, %Shared.Compiled{} = item, item_ctx} <-
           compile_item(
             item_spec,
             ctx |> Shared.Context.enter_property(name) |> Shared.Context.enter_item()
           ) do
      ctx = %{ctx | diagnostics: item_ctx.diagnostics, nodes_left: item_ctx.nodes_left}

      semantic =
        Semantic.Collection.new(name, template_path, item.semantic,
          required?: required?,
          constraints: constraints,
          origins:
            Shared.origin_entries(
              kind: {:map_source, source_path ++ [:kind]},
              min_items: key_origin(spec, :min_items, source_path),
              max_items: key_origin(spec, :max_items, source_path)
            )
        )

      presentation =
        Presentation.Collection.new(semantic.id, item.presentation,
          label: label,
          help: help,
          origins:
            Shared.origin_entries(
              label: label_origin,
              help: key_origin(spec, :help, source_path)
            )
        )

      {:ok, %Shared.Compiled{semantic: semantic, presentation: presentation}, ctx}
    end
  end

  @collection_constraint_keys [:min_items, :max_items]

  defp validate_collection_constraints(spec, name, source_path, template_path, ctx) do
    @collection_constraint_keys
    |> Enum.reduce_while({:ok, %{}}, fn key, {:ok, acc} ->
      case validate_collection_bound(spec, key, name, source_path, template_path, ctx) do
        :absent -> {:cont, {:ok, acc}}
        {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
        {:error, diagnostic} -> {:halt, {:error, diagnostic}}
      end
    end)
    |> case do
      {:ok, constraints} ->
        with :ok <-
               check_bounds(
                 constraints,
                 :min_items,
                 :max_items,
                 name,
                 source_path,
                 template_path,
                 ctx
               ) do
          {:ok, constraints}
        end

      {:error, diagnostic} ->
        {:error, diagnostic}
    end
  end

  defp validate_collection_bound(spec, key, name, source_path, template_path, ctx) do
    case Map.fetch(spec, key) do
      :error ->
        :absent

      {:ok, value} when is_integer(value) and value >= 0 ->
        {:ok, value}

      {:ok, value} ->
        {:error,
         invalid(
           "#{key} for property #{inspect(name)} must be a non-negative integer, " <>
             "got: #{inspect(value)}",
           ctx,
           source_path ++ [key],
           template_path
         )}
    end
  end

  defp fetch_item_spec(spec, name, source_path, template_path, ctx) do
    case Map.fetch(spec, :item) do
      {:ok, item_spec} when is_map(item_spec) ->
        {:ok, item_spec}

      {:ok, other} ->
        {:error,
         invalid(
           "item for property #{inspect(name)} must be a spec map, got: #{inspect(other)}",
           ctx,
           source_path ++ [:item],
           template_path
         )}

      :error ->
        {:error,
         invalid(
           "collection property #{inspect(name)} is missing an :item spec",
           ctx,
           source_path ++ [:item],
           template_path
         )}
    end
  end

  # Item requiredness is cardinality (D-053). Boolean required is
  # stripped with a warning; an object item's required LIST is its
  # ordinary required-properties spelling and passes through; anything
  # else is a strict error — the key is recognized vocabulary here.
  defp resolve_item_required(item_spec, name, source_path, template_path, ctx) do
    case Map.fetch(item_spec, :required) do
      :error ->
        {:ok, item_spec, ctx}

      {:ok, value} when is_boolean(value) ->
        warning = %Diagnostic{
          severity: :warning,
          code: :collection_item_required,
          message:
            "required on the item spec of collection #{inspect(name)} is ignored; " <>
              "item requiredness is cardinality — use min_items",
          origin: {:map_source, source_path ++ [:item, :required]},
          template_path: template_path
        }

        {:ok, Map.delete(item_spec, :required), Shared.Context.add_diagnostic(ctx, warning)}

      {:ok, list} when is_list(list) ->
        if match?(%{kind: :object}, item_spec) do
          {:ok, item_spec, ctx}
        else
          item_required_error(name, list, source_path, template_path, ctx)
        end

      {:ok, other} ->
        item_required_error(name, other, source_path, template_path, ctx)
    end
  end

  defp item_required_error(name, value, source_path, template_path, ctx) do
    {:error,
     invalid(
       "required on the item spec of collection #{inspect(name)} must be a boolean " <>
         "(ignored — use min_items) or, for object items, a list of required " <>
         "property names, got: #{inspect(value)}",
       ctx,
       source_path ++ [:item, :required],
       template_path
     )}
  end

  # Item dispatch: the ctx is already inside the item (enter_property +
  # enter_item), so anonymous nodes use the ctx paths directly.
  defp compile_item(%{kind: :object} = item_spec, item_ctx),
    do: compile_object(item_spec, nil, item_ctx)

  defp compile_item(%{kind: :collection}, item_ctx) do
    unsupported_item(item_ctx, :nested_collection, "nested collections are not yet supported")
  end

  defp compile_item(%{kind: kind} = item_spec, item_ctx) when kind in @scalar_kinds,
    do: compile_field(nil, item_spec, false, item_ctx)

  defp compile_item(%{kind: kind}, item_ctx) when is_atom(kind) do
    unsupported_item(item_ctx, :unsupported_kind, "unsupported kind #{inspect(kind)}")
  end

  defp compile_item(%{kind: kind}, item_ctx) do
    {:error,
     invalid(
       "item kind must be an atom, got: #{inspect(kind)}",
       item_ctx,
       item_ctx.source_path ++ [:kind],
       item_ctx.template_path
     )}
  end

  defp compile_item(item_spec, item_ctx) do
    {:error,
     invalid(
       "item spec has no kind: #{inspect(item_spec)}",
       item_ctx,
       item_ctx.source_path ++ [:kind],
       item_ctx.template_path
     )}
  end

  defp unsupported_item(item_ctx, code, reason) do
    with {:ok, item_ctx} <- Shared.Context.take_budget(item_ctx) do
      origin = {:map_source, item_ctx.source_path ++ [:kind]}

      semantic =
        Semantic.Unsupported.new(nil, item_ctx.template_path,
          origins: Shared.origin_entries(kind: origin)
        )

      diagnostic = %Diagnostic{
        severity: :warning,
        code: code,
        message: "#{reason} for the item template",
        origin: origin,
        template_path: item_ctx.template_path
      }

      {:ok, %Shared.Compiled{semantic: semantic, presentation: nil},
       Shared.Context.add_diagnostic(item_ctx, diagnostic)}
    end
  end

  defp nested_collection_unsupported(name, required?, ctx) do
    with {:ok, ctx} <- Shared.Context.take_budget(ctx) do
      template_path = TemplatePath.child(ctx.template_path, name)
      source_path = ctx.source_path ++ [:properties, name]
      origin = {:map_source, source_path ++ [:kind]}

      semantic =
        Semantic.Unsupported.new(name, template_path,
          required?: required?,
          origins: Shared.origin_entries(kind: origin)
        )

      diagnostic = %Diagnostic{
        severity: :warning,
        code: :nested_collection,
        message: "nested collections are not yet supported for property #{inspect(name)}",
        origin: origin,
        template_path: template_path
      }

      {:ok, %Shared.Compiled{semantic: semantic, presentation: nil},
       Shared.Context.add_diagnostic(ctx, diagnostic)}
    end
  end

  defp validate_constraints(spec, kind, name, source_path, template_path, ctx) do
    @constraint_keys
    |> Enum.reduce_while({:ok, %{}}, fn key, {:ok, acc} ->
      accumulate_constraint(key, acc, spec, kind, name, source_path, template_path, ctx)
    end)
    |> case do
      {:ok, constraints} ->
        validate_constraint_bounds(constraints, name, source_path, template_path, ctx)

      {:error, diagnostic} ->
        {:error, diagnostic}
    end
  end

  defp accumulate_constraint(key, acc, spec, kind, name, source_path, template_path, ctx) do
    case Map.fetch(spec, key) do
      :error ->
        {:cont, {:ok, acc}}

      {:ok, value} ->
        continue_constraint_reduction(
          key,
          value,
          acc,
          kind,
          name,
          source_path,
          template_path,
          ctx
        )
    end
  end

  defp continue_constraint_reduction(key, value, acc, kind, name, source_path, template_path, ctx) do
    case validate_constraint(key, value, kind, name, source_path, template_path, ctx) do
      :ok -> {:cont, {:ok, Map.put(acc, key, value)}}
      {:error, diagnostic} -> {:halt, {:error, diagnostic}}
    end
  end

  defp validate_constraint(key, value, kind, name, source_path, template_path, ctx)
       when key in [:min_length, :max_length] do
    cond do
      kind != :string ->
        {:error,
         invalid(
           "#{key} is only valid for :string properties, got kind #{inspect(kind)} for " <>
             "property #{inspect(name)}",
           ctx,
           source_path ++ [key],
           template_path
         )}

      not (is_integer(value) and value >= 0) ->
        {:error,
         invalid(
           "#{key} for property #{inspect(name)} must be a non-negative integer, " <>
             "got: #{inspect(value)}",
           ctx,
           source_path ++ [key],
           template_path
         )}

      true ->
        :ok
    end
  end

  defp validate_constraint(key, value, kind, name, source_path, template_path, ctx)
       when key in [:min, :max] do
    cond do
      kind not in [:integer, :number] ->
        {:error,
         invalid(
           "#{key} is only valid for :integer or :number properties, got kind " <>
             "#{inspect(kind)} for property #{inspect(name)}",
           ctx,
           source_path ++ [key],
           template_path
         )}

      not is_number(value) ->
        {:error,
         invalid(
           "#{key} for property #{inspect(name)} must be a number, got: #{inspect(value)}",
           ctx,
           source_path ++ [key],
           template_path
         )}

      true ->
        :ok
    end
  end

  defp validate_constraint_bounds(constraints, name, source_path, template_path, ctx) do
    with :ok <-
           check_bounds(
             constraints,
             :min_length,
             :max_length,
             name,
             source_path,
             template_path,
             ctx
           ),
         :ok <- check_bounds(constraints, :min, :max, name, source_path, template_path, ctx) do
      {:ok, constraints}
    end
  end

  defp check_bounds(constraints, low_key, high_key, name, source_path, template_path, ctx) do
    with {:ok, low} <- Map.fetch(constraints, low_key),
         {:ok, high} <- Map.fetch(constraints, high_key) do
      if low <= high do
        :ok
      else
        {:error,
         invalid(
           "#{low_key} (#{inspect(low)}) exceeds #{high_key} (#{inspect(high)}) for " <>
             "property #{inspect(name)}",
           ctx,
           source_path ++ [high_key],
           template_path
         )}
      end
    else
      :error -> :ok
    end
  end

  defp compile_field(name, %{kind: kind} = spec, required?, ctx) when kind in @scalar_kinds do
    {template_path, source_path} = field_location(name, ctx)

    with {:ok, ctx} <- Shared.Context.take_budget(ctx),
         {:ok, examples, examples_origin} <-
           fetch_examples(spec, name, source_path, template_path, ctx),
         {:ok, options, options_origin, ctx} <-
           fetch_one_of_options(spec, name, source_path, template_path, ctx),
         {:ok, {label, label_origin}} <-
           resolve_label(spec, name, source_path, template_path, ctx),
         {:ok, help} <-
           fetch_optional_string(
             spec,
             :help,
             subject(name, template_path),
             source_path,
             template_path,
             ctx
           ),
         {:ok, {role, role_origin}} <-
           resolve_role(spec, name, source_path, template_path, ctx),
         {:ok, widget} <-
           fetch_optional_atom(
             spec,
             :widget,
             subject(name, template_path),
             source_path,
             template_path,
             ctx
           ),
         {:ok, {default, default_origin, ctx}} <-
           resolve_default(spec, name, kind, source_path, template_path, ctx),
         {:ok, constraints} <-
           validate_constraints(spec, kind, name, source_path, template_path, ctx) do
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
          options: options_origin,
          examples: examples_origin,
          default: default_origin,
          hidden: hidden_origin,
          read_only: read_only_origin
        )

      semantic =
        Semantic.Field.new(name, template_path, kind,
          role: role,
          required?: required?,
          read_only?: read_only,
          options: options,
          default: default,
          examples: examples,
          constraints: constraints,
          origins: semantic_origins(origins)
        )

      presentation =
        Presentation.Field.new(semantic.id,
          label: label,
          help: help,
          widget: widget,
          hidden?: hidden,
          origins: presentation_origins(origins)
        )

      {:ok, %Shared.Compiled{semantic: semantic, presentation: presentation}, ctx}
    end
  end

  defp fetch_examples(spec, name, source_path, template_path, ctx) do
    case Map.fetch(spec, :examples) do
      {:ok, examples} when is_list(examples) ->
        {:ok, examples, {:map_source, source_path ++ [:examples]}}

      {:ok, other} ->
        {:error,
         invalid(
           "property #{inspect(name)} examples: expected a list, got: #{inspect(other)}",
           ctx,
           source_path ++ [:examples],
           template_path
         )}

      :error ->
        {:ok, nil, nil}
    end
  end

  defp resolve_default(spec, name, kind, source_path, template_path, ctx) do
    case Map.fetch(spec, :default) do
      {:ok, nil} ->
        warning = %Diagnostic{
          severity: :warning,
          code: :unsupported_keyword,
          message: "nil default for property #{inspect(name)} is ignored",
          origin: {:map_source, source_path ++ [:default]},
          template_path: template_path
        }

        {:ok, {nil, nil, Shared.Context.add_diagnostic(ctx, warning)}}

      {:ok, value} ->
        if default_compatible?(kind, value) do
          {:ok, {value, {:map_source, source_path ++ [:default]}, ctx}}
        else
          {:error,
           invalid(
             "default for property #{inspect(name)} must be #{kind_article(kind)} #{kind}, " <>
               "got: #{inspect(value)}",
             ctx,
             source_path ++ [:default],
             template_path
           )}
        end

      :error ->
        {:ok, {nil, nil, ctx}}
    end
  end

  defp default_compatible?(:string, value), do: is_binary(value)
  defp default_compatible?(:integer, value), do: is_integer(value)
  defp default_compatible?(:number, value), do: is_number(value)
  defp default_compatible?(:boolean, value), do: is_boolean(value)

  defp kind_article(:integer), do: "an"
  defp kind_article(_kind), do: "a"

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

        {false, nil, Shared.Context.add_diagnostic(ctx, warning)}

      :error ->
        {false, nil, ctx}
    end
  end

  defp invalid(message, ctx, origin_path \\ nil, template_path \\ nil) do
    %Diagnostic{
      severity: :error,
      code: :invalid_declaration,
      message: message,
      origin: {:map_source, origin_path || ctx.source_path},
      template_path: template_path || ctx.template_path
    }
  end

  defp fetch_optional_string(map, key, subject, source_path, template_path, ctx) do
    case Map.get(map, key) do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        {:ok, value}

      other ->
        {:error,
         invalid(
           "#{key} for #{subject} must be a string, got: #{inspect(other)}",
           ctx,
           source_path ++ [key],
           template_path
         )}
    end
  end

  defp resolve_label(%{title: title}, _name, source_path, _template_path, _ctx)
       when is_binary(title) do
    {:ok, {title, {:map_source, source_path ++ [:title]}}}
  end

  defp resolve_label(%{title: title}, name, source_path, template_path, ctx)
       when not is_nil(title) do
    {:error,
     invalid(
       "title for #{subject(name, template_path)} must be a string, got: #{inspect(title)}",
       ctx,
       source_path ++ [:title],
       template_path
     )}
  end

  defp resolve_label(_spec, nil, _source_path, _template_path, _ctx), do: {:ok, {nil, nil}}

  defp resolve_label(_spec, name, _source_path, _template_path, _ctx) do
    {:ok, {Shared.humanize(name), {:inference, :label_from_name}}}
  end

  # An anonymous node is either the root object or a collection's item
  # template; the template path tells them apart.
  defp subject(nil, %TemplatePath{segments: segments}) do
    if List.last(segments) == :item, do: "the item template", else: "the root object"
  end

  defp subject(name, _template_path), do: "property #{inspect(name)}"

  # A named field/property derives its own location; the anonymous item
  # template is compiled inside an already-entered item context.
  defp field_location(nil, ctx), do: {ctx.template_path, ctx.source_path}

  defp field_location(name, ctx),
    do: {TemplatePath.child(ctx.template_path, name), ctx.source_path ++ [:properties, name]}

  defp resolve_role(%{role: role}, _name, source_path, _template_path, _ctx)
       when is_atom(role) and not is_nil(role) do
    {:ok, {role, {:map_source, source_path ++ [:role]}}}
  end

  defp resolve_role(%{role: role}, name, source_path, template_path, ctx) when not is_nil(role) do
    {:error,
     invalid(
       "role for #{subject(name, template_path)} must be an atom, got: #{inspect(role)}",
       ctx,
       source_path ++ [:role],
       template_path
     )}
  end

  defp resolve_role(%{one_of: options}, _name, _source_path, _template_path, _ctx)
       when is_list(options) do
    {:ok, {:select, {:inference, :one_of_select}}}
  end

  defp resolve_role(%{kind: kind}, _name, _source_path, _template_path, _ctx) do
    {role, rule} = Map.fetch!(@role_defaults, kind)
    {:ok, {role, {:inference, rule}}}
  end

  defp fetch_optional_atom(map, key, subject, source_path, template_path, ctx) do
    case Map.get(map, key) do
      nil ->
        {:ok, nil}

      value when is_atom(value) ->
        {:ok, value}

      other ->
        {:error,
         invalid(
           "#{key} for #{subject} must be an atom, got: #{inspect(other)}",
           ctx,
           source_path ++ [key],
           template_path
         )}
    end
  end

  defp key_origin(spec, key, source_path) do
    if Map.has_key?(spec, key), do: {:map_source, source_path ++ [key]}
  end

  defp scalar_option?(value) do
    is_binary(value) or is_number(value) or is_boolean(value)
  end

  defp fetch_one_of_options(spec, name, source_path, template_path, ctx) do
    case Map.fetch(spec, :one_of) do
      {:ok, options} when is_list(options) ->
        case validate_scalar_options(options, name, source_path, template_path, ctx) do
          {:ok, options, origin} -> {:ok, options, origin, ctx}
          {:error, diagnostic} -> {:error, diagnostic}
        end

      {:ok, nil} ->
        warning = %Diagnostic{
          severity: :warning,
          code: :unsupported_keyword,
          message: "nil one_of for property #{inspect(name)} is ignored",
          origin: {:map_source, source_path ++ [:one_of]},
          template_path: template_path
        }

        {:ok, nil, nil, Shared.Context.add_diagnostic(ctx, warning)}

      {:ok, other} ->
        {:error,
         invalid(
           "property #{inspect(name)} one_of: expected a list, got: #{inspect(other)}",
           ctx,
           source_path ++ [:one_of],
           template_path
         )}

      :error ->
        {:ok, nil, nil, ctx}
    end
  end

  defp validate_scalar_options(options, name, source_path, template_path, ctx) do
    case Enum.find(Enum.with_index(options), fn {value, _index} -> not scalar_option?(value) end) do
      nil ->
        {:ok, options, {:map_source, source_path ++ [:one_of]}}

      {invalid_value, index} ->
        origin_path = source_path ++ [:one_of, index]

        message =
          "one_of option #{index} for property #{inspect(name)} must be a string, number, or boolean, got: #{inspect(invalid_value)}"

        {:error, invalid(message, ctx, origin_path, template_path)}
    end
  end

  @semantic_origin_keys [:role, :options, :examples, :default, :read_only]
  @presentation_origin_keys [:label, :widget, :help, :hidden]

  defp semantic_origins(origins), do: Shared.fact_origins(origins, @semantic_origin_keys)
  defp presentation_origins(origins), do: Shared.fact_origins(origins, @presentation_origin_keys)

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

    spec = %Shared.PresentationGroupSpec{
      id: id,
      label: label,
      label_origin: label_origin,
      fields: member_names
    }

    {children, unknown} =
      attach_presentation_group(children, compiled_children, spec, ctx.template_path)

    ctx = warn_unknown_members(unknown, id, ctx)

    {children, ctx}
  end

  defp attach_presentation_group(
         children,
         compiled_children,
         %Shared.PresentationGroupSpec{fields: field_names} = spec,
         template_path
       ) do
    field_names = Enum.uniq(field_names)
    semantic_children = Enum.map(compiled_children, & &1.semantic)
    presentation_by_name = Shared.presentation_children_by_name(children, semantic_children)
    unsupported_names = Shared.unsupported_names(semantic_children)

    unknown =
      Enum.reject(
        field_names,
        &(is_map_key(presentation_by_name, &1) or MapSet.member?(unsupported_names, &1))
      )

    members =
      field_names
      |> Enum.filter(&is_map_key(presentation_by_name, &1))
      |> Enum.map(&Map.fetch!(presentation_by_name, &1))

    {place_presentation_group(children, spec, members, template_path), unknown}
  end

  defp place_presentation_group(children, _spec, [], _template_path), do: children

  defp place_presentation_group(
         children,
         %Shared.PresentationGroupSpec{id: id} = spec,
         members,
         template_path
       ) do
    group =
      Presentation.Group.new(NodeId.group(template_path, id), members,
        label: spec.label,
        origins: Shared.origin_entries(label: spec.label_origin)
      )

    member_ids = MapSet.new(members, & &1.semantic_id)
    first_index = Enum.find_index(children, &(Shared.presentation_reference_id(&1) in member_ids))

    children
    |> Enum.reject(&(Shared.presentation_reference_id(&1) in member_ids))
    |> List.insert_at(first_index, group)
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

      Shared.Context.add_diagnostic(ctx, diagnostic)
    end)
  end
end
