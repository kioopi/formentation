defmodule Formentation.Source.Shared do
  @moduledoc false

  alias Formentation.Definition.Finalizer
  alias Formentation.{Diagnostic, Presentation, Semantic, TemplatePath}

  defmodule Context do
    @moduledoc false
    defstruct template_path: %TemplatePath{segments: []},
              source_path: [],
              diagnostics: [],
              depth: 0,
              max_depth: 16,
              nodes_left: 1_000
  end

  defmodule Compiled do
    @moduledoc false

    defstruct [:semantic, :presentation]
  end

  defmodule PresentationGroupSpec do
    @moduledoc false

    defstruct [:id, :label, :label_origin, :fields]
  end

  def context(opts) do
    %Context{
      max_depth: Keyword.get(opts, :max_depth, 16),
      nodes_left: Keyword.get(opts, :max_nodes, 1_000)
    }
  end

  def humanize(name), do: name |> String.replace("_", " ") |> String.capitalize()

  def origin_entries(entries) do
    for {key, origin} <- entries, origin != nil, do: {key, origin}
  end

  def compile_compiled_impl(source, opts, compile_object_fn) do
    ctx = context(opts)

    case compile_object_fn.(source, nil, ctx) do
      {:ok, %Compiled{} = compiled, ctx} ->
        finalize_compiled(compiled, ctx)

      {:error, %Diagnostic{} = diagnostic} ->
        {:error, [diagnostic]}
    end
  end

  def finalize_compiled(%Compiled{} = compiled, %Context{} = ctx) do
    diagnostics = Enum.reverse(ctx.diagnostics, policy_diagnostics(compiled.semantic))

    case Finalizer.finalize(compiled.semantic, compiled.presentation, diagnostics: diagnostics) do
      {:ok, definition} -> {:ok, definition, diagnostics}
      {:error, finalizer_diagnostics} -> {:error, finalizer_diagnostics}
    end
  end

  def require_compiled_object(%Compiled{} = compiled, child_ctx, ctx, required?) do
    {:ok, %{compiled | semantic: %{compiled.semantic | required?: required?}},
     %{ctx | diagnostics: child_ctx.diagnostics, nodes_left: child_ctx.nodes_left}}
  end

  def fact_origins(origins, allowed_keys) do
    Enum.filter(origins, fn {key, _origin} -> key in allowed_keys end)
  end

  def presentation_reference_id(%Presentation.Field{semantic_id: semantic_id}), do: semantic_id
  def presentation_reference_id(%Presentation.Object{semantic_id: semantic_id}), do: semantic_id
  def presentation_reference_id(%Presentation.Group{}), do: nil

  def presentation_children_by_name(children, semantic_children) do
    semantic_name_by_id = Map.new(semantic_children, &{&1.id, &1.name})

    children
    |> Enum.map(fn child ->
      case presentation_reference_id(child) do
        nil -> nil
        semantic_id -> {Map.fetch!(semantic_name_by_id, semantic_id), child}
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  def unsupported_names(semantic_children) do
    semantic_children
    |> Enum.filter(&match?(%Semantic.Unsupported{}, &1))
    |> Enum.map(& &1.name)
    |> MapSet.new()
  end

  @reserved_names ["_csrf_token", "_target"]
  @reserved_prefix "_unused_"

  defp policy_diagnostics(root), do: root |> collect_policy_warnings([]) |> Enum.reverse()

  defp collect_policy_warnings(node, acc) do
    acc = maybe_reserved_name(node, acc)
    acc = maybe_required_permits_empty(node, acc)
    Enum.reduce(children_of(node), acc, fn child, acc -> collect_policy_warnings(child, acc) end)
  end

  defp children_of(%Semantic.Object{children: children}), do: children
  defp children_of(_leaf), do: []

  defp maybe_reserved_name(%{name: name} = node, acc) when is_binary(name) do
    if name in @reserved_names or String.starts_with?(name, @reserved_prefix) do
      warning =
        policy_warning(
          :reserved_property_name,
          "property #{inspect(name)} collides with a reserved transport name and " <>
            "would be stripped by transport normalization (D-014)",
          node
        )

      [warning | acc]
    else
      acc
    end
  end

  defp maybe_reserved_name(_node, acc), do: acc

  # A required string without minLength >= 1 accepts "" — JSON Schema's
  # required checks presence, not blankness (D-010). A fixed option set
  # without "" already forbids empty input, so it is exempt.
  defp maybe_required_permits_empty(
         %Semantic.Field{value_type: :string, required?: true} = node,
         acc
       ) do
    min_length = Map.get(node.constraints, :min_length, 0)
    empty_option? = node.options == nil or "" in node.options

    if min_length < 1 and empty_option? do
      warning =
        policy_warning(
          :required_permits_empty,
          "required property #{inspect(node.name)} permits an empty string; " <>
            "add minLength: 1 if non-empty input is intended",
          node
        )

      [warning | acc]
    else
      acc
    end
  end

  defp maybe_required_permits_empty(_node, acc), do: acc

  defp policy_warning(code, message, node) do
    %Diagnostic{
      severity: :warning,
      code: code,
      message: message,
      origin: nil,
      template_path: node.template_path
    }
  end
end
