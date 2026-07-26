defmodule Formentation.Source.Shared do
  @moduledoc false

  alias Formentation.{Definition, Diagnostic, Node, NodeId, TemplatePath}

  defmodule Context do
    @moduledoc false
    defstruct template_path: %TemplatePath{segments: []},
              source_path: [],
              diagnostics: [],
              depth: 0,
              max_depth: 16,
              nodes_left: 1_000
  end

  def humanize(name), do: name |> String.replace("_", " ") |> String.capitalize()

  def origin_entries(entries) do
    for {key, origin} <- entries, origin != nil, do: {key, origin}
  end

  def create_group_node(name, children, ctx, opts) do
    %Node.Group{
      id: NodeId.from_path(ctx.template_path),
      nests_data?: true,
      name: name,
      label: opts[:label],
      help: opts[:help],
      template_path: ctx.template_path,
      origins: origin_entries(label: opts[:label_origin], help: opts[:help_origin]),
      children: children
    }
  end

  # Temporary compatibility evidence for Issue #16: presentation grouping
  # can move siblings, so semantic declaration order is stamped before
  # grouping. The split storage planned in Issue #18 should make this
  # field unnecessary.
  def stamp_declaration_order(children) do
    children
    |> Enum.with_index()
    |> Enum.map(fn {child, index} -> %{child | declaration_order: index} end)
  end

  @doc """
  Stamps members with the group id and inserts a presentation-group node
  at the first member's position. Members follow the group's `fields`
  list order — the fields list is data, so its order is meaningful
  (spec section 4). Returns the reordered children and the member names
  that matched no child (for adapter-specific warnings). A group with no
  known members inserts no node.
  """
  @spec attach_group([Node.t()], map(), TemplatePath.t()) :: {[Node.t()], [String.t()]}
  def attach_group(children, %{id: id, fields: field_names} = spec, template_path) do
    field_names = Enum.uniq(field_names)
    by_name = Map.new(children, &{&1.name, &1})
    unknown = Enum.reject(field_names, &is_map_key(by_name, &1))

    members =
      for name <- field_names, is_map_key(by_name, name) do
        stamp_membership(Map.fetch!(by_name, name), id)
      end

    {place_group(children, spec, members, template_path), unknown}
  end

  defp stamp_membership(%Node.Field{} = member, id), do: %{member | group: id}
  defp stamp_membership(member, _id), do: member

  defp place_group(children, _spec, [], _template_path), do: children

  defp place_group(children, %{id: id} = spec, members, template_path) do
    group_node = %Node.Group{
      id: NodeId.group(template_path, id),
      nests_data?: false,
      label: spec[:label],
      template_path: template_path,
      origins: origin_entries(label: spec[:label_origin]),
      children: members
    }

    member_names = MapSet.new(members, & &1.name)
    first_index = Enum.find_index(children, &(&1.name in member_names))

    children
    |> Enum.reject(&(&1.name in member_names))
    |> List.insert_at(first_index, group_node)
  end

  def compile_impl(source, opts, compile_object_fn) do
    ctx = %Context{
      max_depth: Keyword.get(opts, :max_depth, 16),
      nodes_left: Keyword.get(opts, :max_nodes, 1_000)
    }

    case compile_object_fn.(source, nil, ctx) do
      {:ok, root, ctx} ->
        finalize_legacy(root, ctx)

      {:error, %Diagnostic{} = diagnostic} ->
        {:error, [diagnostic]}
    end
  end

  def finalize_legacy(root, %Context{} = ctx, attrs \\ []) do
    diagnostics = Enum.reverse(ctx.diagnostics, policy_diagnostics(root))

    definition =
      attrs
      |> Keyword.merge(root: root, format_version: 2, diagnostics: diagnostics)
      |> then(&struct!(Definition, &1))

    {:ok, definition, diagnostics}
  end

  @reserved_names ["_csrf_token", "_target"]
  @reserved_prefix "_unused_"

  defp policy_diagnostics(root), do: root |> collect_policy_warnings([]) |> Enum.reverse()

  defp collect_policy_warnings(node, acc) do
    acc = maybe_reserved_name(node, acc)
    acc = maybe_required_permits_empty(node, acc)
    Enum.reduce(children_of(node), acc, fn child, acc -> collect_policy_warnings(child, acc) end)
  end

  defp children_of(%Node.Group{children: children}), do: children
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
         %Node.Field{value_type: :string, required?: true} = node,
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
