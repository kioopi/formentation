defmodule Formentation.Source.Shared do
  @moduledoc false

  alias Formentation.Definition.{Finalizer, Presentation, Semantic}
  alias Formentation.{Diagnostic, TemplatePath}

  defmodule Dialect do
    @moduledoc false

    @doc "Noun used in this adapter's budget diagnostics."
    @callback noun() :: String.t()

    @doc "Builds this adapter's origin tag from a source path."
    @callback origin(source_path :: list()) :: Formentation.Origin.t()

    @doc "This adapter's source-path segment for a named object property."
    @callback property_segment(name :: String.t()) :: list()

    @doc "This adapter's source-path segments for a collection item declaration."
    @callback item_segment() :: list()
  end

  defmodule Context do
    @moduledoc false
    defstruct template_path: %TemplatePath{segments: []},
              source_path: [],
              diagnostics: [],
              depth: 0,
              max_depth: 16,
              nodes_left: 1_000,
              dialect: nil

    def check_depth(%__MODULE__{depth: depth, max_depth: max_depth} = ctx)
        when depth > max_depth do
      {:error,
       budget_diagnostic(
         :max_depth_exceeded,
         "#{ctx.dialect.noun()} exceeds maximum depth of #{max_depth}",
         ctx
       )}
    end

    def check_depth(%__MODULE__{}), do: :ok

    def take_budget(%__MODULE__{nodes_left: nodes_left} = ctx) when nodes_left <= 0 do
      {:error,
       budget_diagnostic(
         :max_nodes_exceeded,
         "#{ctx.dialect.noun()} node budget exhausted",
         ctx
       )}
    end

    def take_budget(%__MODULE__{nodes_left: nodes_left} = ctx) do
      {:ok, %{ctx | nodes_left: nodes_left - 1}}
    end

    def enter_property(%__MODULE__{} = ctx, name) when is_binary(name) do
      %{
        ctx
        | depth: ctx.depth + 1,
          template_path: TemplatePath.child(ctx.template_path, name),
          source_path: ctx.source_path ++ ctx.dialect.property_segment(name)
      }
    end

    def enter_item(%__MODULE__{} = ctx) do
      %{
        ctx
        | depth: ctx.depth + 1,
          template_path: TemplatePath.item(ctx.template_path),
          source_path: ctx.source_path ++ ctx.dialect.item_segment()
      }
    end

    def add_diagnostic(%__MODULE__{} = ctx, %Diagnostic{} = diagnostic) do
      %{ctx | diagnostics: [diagnostic | ctx.diagnostics]}
    end

    defp budget_diagnostic(code, message, %__MODULE__{} = ctx) do
      %Diagnostic{
        severity: :error,
        code: code,
        message: message,
        origin: ctx.dialect.origin(ctx.source_path),
        template_path: ctx.template_path
      }
    end
  end

  defmodule Compiled do
    @moduledoc false

    defstruct [:semantic, :presentation]
  end

  defmodule Build do
    @moduledoc false

    defstruct [:semantic, :presentation, :validation, diagnostics: []]
  end

  defmodule PresentationGroupSpec do
    @moduledoc false

    defstruct [:id, :label, :label_origin, :fields]
  end

  def context(dialect, opts) when is_atom(dialect) do
    %Context{
      dialect: dialect,
      max_depth: Keyword.get(opts, :max_depth, 16),
      nodes_left: Keyword.get(opts, :max_nodes, 1_000)
    }
  end

  def humanize(name), do: name |> String.replace("_", " ") |> String.capitalize()

  def origin_entries(entries) do
    for {key, origin} <- entries, origin != nil, do: {key, origin}
  end

  def walk(source, dialect, opts, compile_object_fn) do
    ctx = context(dialect, opts)

    case compile_object_fn.(source, nil, ctx) do
      {:ok, %Compiled{} = compiled, ctx} ->
        {:ok, build(compiled, ctx)}

      {:error, %Diagnostic{} = diagnostic} ->
        {:error, [diagnostic]}
    end
  end

  def build(%Compiled{} = compiled, %Context{} = ctx) do
    %Build{
      semantic: compiled.semantic,
      presentation: compiled.presentation,
      diagnostics: Enum.reverse(ctx.diagnostics, policy_diagnostics(compiled.semantic))
    }
  end

  def finalize(%Build{} = build) do
    case Finalizer.finalize(build.semantic, build.presentation,
           diagnostics: build.diagnostics,
           validation: build.validation
         ) do
      {:ok, definition} -> {:ok, definition, build.diagnostics}
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

  def presentation_reference_id(%Presentation.Collection{semantic_id: semantic_id}),
    do: semantic_id

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

  @reserved_names ["_csrf_token", "_target", "_persistent_id"]
  @reserved_prefix "_unused_"

  defp policy_diagnostics(root), do: root |> collect_policy_warnings([]) |> Enum.reverse()

  defp collect_policy_warnings(node, acc) do
    acc = maybe_reserved_name(node, acc)
    acc = maybe_required_permits_empty(node, acc)
    Enum.reduce(children_of(node), acc, fn child, acc -> collect_policy_warnings(child, acc) end)
  end

  defp children_of(%Semantic.Object{children: children}), do: children
  defp children_of(%Semantic.Collection{item: item}), do: [item]
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
