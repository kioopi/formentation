defmodule Formentation.Definition.Finalizer do
  @moduledoc false

  alias Formentation.{
    Definition,
    Diagnostic,
    TemplatePath
  }

  alias Formentation.Definition.{Presentation, Semantic}

  defmodule Seen do
    @moduledoc false

    defstruct layout_ids: %{}, references: %{}

    @type t :: %__MODULE__{
            layout_ids: %{String.t() => true},
            references: %{String.t() => true}
          }
  end

  @spec finalize(Semantic.Object.t(), Presentation.Object.t(), keyword()) ::
          {:ok, Definition.t()} | {:error, [Diagnostic.t()]}
  def finalize(%Semantic.Object{} = semantic, %Presentation.Object{} = presentation, opts \\ []) do
    with {:ok, semantic_index} <- validate_semantic(semantic),
         :ok <- validate_presentation(presentation, semantic_index) do
      definition = %Definition{
        format_version: Definition.format_version(),
        semantic: semantic,
        semantic_index: semantic_index,
        presentation: presentation,
        validation: Keyword.get(opts, :validation),
        diagnostics: Keyword.get(opts, :diagnostics, [])
      }

      {:ok, definition}
    else
      {:error, %Diagnostic{} = diagnostic} ->
        {:error, [diagnostic]}
    end
  end

  defp validate_semantic(%Semantic.Object{template_path: %TemplatePath{segments: []}} = root) do
    collect_semantic(root, %Semantic.Index{}, nil)
  end

  defp validate_semantic(%Semantic.Object{} = root) do
    invariant!(
      :invalid_semantic_root,
      "semantic root must be an object at the root template path",
      root
    )
  end

  defp collect_semantic(%Semantic.Object{} = object, index, parent_path) do
    with :ok <- validate_object_template_path(object, parent_path),
         {:ok, index} <- put_semantic(object, :object, index) do
      collect_semantic_children(object, index)
    end
  end

  defp collect_semantic(%Semantic.Field{} = field, index, parent_path) do
    :ok = validate_child_template_path(field, parent_path)
    put_semantic(field, :field, index)
  end

  defp collect_semantic(%Semantic.Unsupported{} = unsupported, index, parent_path) do
    :ok = validate_child_template_path(unsupported, parent_path)
    put_semantic(unsupported, :unsupported, index)
  end

  defp collect_semantic(node, _index, _parent_path) do
    invariant!(
      :invalid_semantic_child,
      "semantic children must be semantic object, field, or unsupported occurrences",
      node
    )
  end

  defp collect_semantic_children(%Semantic.Object{} = object, index) do
    case reject_duplicate_child_names(object) do
      :ok -> reduce_semantic_children(object.children, index, object.template_path)
      {:error, diagnostic} -> {:error, diagnostic}
    end
  end

  defp reduce_semantic_children(children, index, parent_path) do
    Enum.reduce_while(children, {:ok, index}, fn child, {:ok, index} ->
      case collect_semantic(child, index, parent_path) do
        {:ok, index} -> {:cont, {:ok, index}}
        {:error, diagnostic} -> {:halt, {:error, diagnostic}}
      end
    end)
  end

  defp validate_object_template_path(%Semantic.Object{template_path: path}, nil) do
    if path.segments == [] do
      :ok
    else
      invariant!(:invalid_semantic_root, "semantic root must be at the root template path", nil)
    end
  end

  defp validate_object_template_path(%Semantic.Object{} = object, parent_path),
    do: validate_child_template_path(object, parent_path)

  defp validate_child_template_path(
         %{name: name, template_path: %TemplatePath{} = path} = node,
         parent_path
       )
       when is_binary(name) do
    expected = %TemplatePath{segments: parent_path.segments ++ [name]}

    if path == expected do
      :ok
    else
      invariant!(
        :invalid_semantic_template_path,
        "semantic child template path must equal the parent path plus its name",
        node
      )
    end
  end

  defp validate_child_template_path(node, _parent_path) do
    invariant!(:invalid_semantic_name, "semantic child name must be a string", node)
  end

  defp reject_duplicate_child_names(%Semantic.Object{children: children} = object) do
    {_seen, duplicate} =
      Enum.reduce_while(children, {MapSet.new(), nil}, fn child, {seen, nil} ->
        name = Map.get(child, :name)

        if MapSet.member?(seen, name) do
          {:halt, {seen, child}}
        else
          {:cont, {MapSet.put(seen, name), nil}}
        end
      end)

    case duplicate do
      nil ->
        :ok

      child ->
        {:error,
         source_diagnostic(
           :duplicate_property_name,
           "duplicate semantic child name #{inspect(child.name)}",
           child,
           object
         )}
    end
  end

  defp put_semantic(%{id: id, template_path: template_path} = node, kind, index) do
    cond do
      Map.has_key?(index.by_id, id) ->
        invariant!(:duplicate_semantic_id, "duplicate semantic id #{inspect(id)}", node)

      Map.has_key?(index.by_template_path, template_path) ->
        invariant!(
          :duplicate_semantic_template_path,
          "duplicate semantic template path #{inspect(template_path.segments)}",
          node
        )

      true ->
        entry = %{kind: kind, node: node}

        {:ok,
         %Semantic.Index{
           by_id: Map.put(index.by_id, id, entry),
           by_template_path: Map.put(index.by_template_path, template_path, entry)
         }}
    end
  end

  defp validate_presentation(%Presentation.Object{} = root, semantic_index) do
    seen = %Seen{}

    with :ok <- expect_reference(root, :object, semantic_index),
         {:ok, seen} <- walk_presentation(root, semantic_index, seen) do
      require_complete_references(semantic_index, seen)
    end
  end

  defp walk_presentation(%Presentation.Object{} = object, semantic_index, seen) do
    with :ok <- expect_reference(object, :object, semantic_index),
         {:ok, seen} <- put_layout_id(object, seen),
         {:ok, seen} <- put_reference(object, seen) do
      walk_presentation_children(object.children, semantic_index, seen)
    end
  end

  defp walk_presentation(%Presentation.Group{} = group, semantic_index, seen) do
    {:ok, seen} = put_layout_id(group, seen)
    walk_presentation_children(group.children, semantic_index, seen)
  end

  defp walk_presentation(%Presentation.Field{} = field, semantic_index, seen) do
    with :ok <- expect_reference(field, :field, semantic_index),
         {:ok, seen} <- put_layout_id(field, seen) do
      put_reference(field, seen)
    end
  end

  defp walk_presentation(node, _semantic_index, _seen) do
    invariant!(
      :invalid_presentation_child,
      "presentation children must be object, field, or group descriptors",
      node
    )
  end

  defp walk_presentation_children(children, semantic_index, seen) do
    Enum.reduce_while(children, {:ok, seen}, fn child, {:ok, seen} ->
      case walk_presentation(child, semantic_index, seen) do
        {:ok, seen} -> {:cont, {:ok, seen}}
        {:error, diagnostic} -> {:halt, {:error, diagnostic}}
      end
    end)
  end

  defp expect_reference(%{semantic_id: semantic_id} = node, expected_kind, semantic_index) do
    case Map.get(semantic_index.by_id, semantic_id) do
      nil ->
        invariant!(
          :dangling_presentation_reference,
          "presentation reference #{inspect(semantic_id)} does not resolve",
          node
        )

      %{kind: :unsupported} ->
        invariant!(
          :unsupported_presentation_reference,
          "presentation reference #{inspect(semantic_id)} targets an unsupported occurrence",
          node
        )

      %{kind: ^expected_kind} ->
        :ok

      %{kind: found_kind} ->
        invariant!(
          :kind_mismatched_presentation_reference,
          "presentation reference #{inspect(semantic_id)} expected #{expected_kind}, got #{found_kind}",
          node
        )
    end
  end

  defp put_layout_id(%{id: id} = node, seen) do
    if Map.has_key?(seen.layout_ids, id) do
      invariant!(:duplicate_layout_id, "duplicate layout id #{inspect(id)}", node)
    else
      {:ok, %{seen | layout_ids: Map.put(seen.layout_ids, id, true)}}
    end
  end

  defp put_reference(%{semantic_id: semantic_id} = node, seen) do
    if Map.has_key?(seen.references, semantic_id) do
      invariant!(
        :duplicate_presentation_reference,
        "duplicate presentation reference #{inspect(semantic_id)}",
        node
      )
    else
      {:ok, %{seen | references: Map.put(seen.references, semantic_id, true)}}
    end
  end

  defp require_complete_references(semantic_index, seen) do
    semantic_index.by_id
    |> Enum.reject(fn {_id, %{kind: kind}} -> kind == :unsupported end)
    |> Enum.map(fn {id, _entry} -> id end)
    |> Enum.reject(&Map.has_key?(seen.references, &1))
    |> Enum.sort()
    |> case do
      [] ->
        :ok

      [semantic_id | _rest] ->
        invariant!(
          :missing_presentation_reference,
          "supported semantic occurrence #{inspect(semantic_id)} has no presentation reference",
          nil
        )
    end
  end

  defp source_diagnostic(code, message, node, fallback_node) do
    %Diagnostic{
      severity: :error,
      code: code,
      message: message,
      origin: origin(node) || origin(fallback_node),
      template_path: template_path(node) || template_path(fallback_node)
    }
  end

  defp invariant!(code, message, node) do
    raise ArgumentError,
          "invalid definition invariant #{inspect(code)}: " <>
            message <> invariant_location(node)
  end

  defp invariant_location(%{id: id}) when is_binary(id), do: " at #{inspect(id)}"
  defp invariant_location(_node), do: ""

  defp origin(%{origins: origins}) when is_list(origins) do
    origins
    |> List.first()
    |> case do
      {_fact, origin} -> origin
      nil -> nil
    end
  end

  defp origin(_node), do: nil

  defp template_path(%{template_path: %TemplatePath{} = path}), do: path
  defp template_path(_node), do: nil
end
