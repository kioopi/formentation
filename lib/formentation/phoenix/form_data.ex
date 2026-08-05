defimpl Phoenix.HTML.FormData, for: Formentation.Form do
  # Projection only (D-009): this implementation owns no decoding, no
  # validation, no transitions. `form.params` is the Phoenix-compatible
  # view so `Phoenix.Component.used_input?/1` keeps working (D-014).
  # Spec: docs/superpowers/specs/2026-07-23-phase1-step5-formdata-design.md

  alias Formentation.{Form, Info, Semantic}
  alias Formentation.Phoenix.ProjectedForm

  def to_form(form_state, opts) do
    reject_owned_option!(opts, :action)
    reject_owned_option!(opts, :errors)
    {name, opts} = Keyword.pop(opts, :as)
    {id, opts} = Keyword.pop(opts, :id)

    name = name && to_string(name)
    id = id || name

    unless is_binary(id) or is_nil(id) do
      raise ArgumentError, ":id option must be a binary/string, got: #{inspect(id)}"
    end

    %Phoenix.HTML.Form{
      source: form_state,
      impl: __MODULE__,
      id: id,
      name: name,
      params: form_state.params || %{},
      data: form_state.original,
      errors: errors_for(form_state, []),
      action: form_state.action,
      hidden: [],
      options: ProjectedForm.put_root_path(opts, [])
    }
  end

  def to_form(form_state, form, field, opts) when is_atom(field) or is_binary(field) do
    key = field_to_string(field)
    path = ProjectedForm.root_segments!(form) ++ [key]

    case Info.semantic_kind(form_state.definition, path) do
      :object -> [nested_form(form_state, form, key, path, opts)]
      other -> raise_not_nested!(field, other)
    end
  end

  defp raise_not_nested!(field, kind) do
    kind = if kind, do: inspect(kind), else: "no node"

    raise ArgumentError,
          "inputs_for is only supported for data-nesting objects; " <>
            "#{inspect(field)} resolves to #{kind}"
  end

  defp nested_form(form_state, form, key, path, opts) do
    reject_owned_option!(opts, :action)
    reject_owned_option!(opts, :errors)
    opts = drop_collection_options!(opts)
    {name, opts} = Keyword.pop(opts, :as)
    {id, opts} = Keyword.pop(opts, :id)
    # Phoenix.HTML.Form.t()'s spec narrows id/name to binaries, but the
    # anonymous-form boundary (`to_form(state, [])`) intentionally supports
    # nil at runtime. Reading through Map.get/2 keeps Dialyzer from judging
    # the nil clauses of join_id/2 and join_name/2 unreachable; direct
    # `form.id` access reports two pattern_match errors here. Map.get/2 takes
    # the struct as-is, so this costs nothing beyond the lookup.

    %Phoenix.HTML.Form{
      source: form_state,
      impl: __MODULE__,
      id: (id && to_string(id)) || join_id(Map.get(form, :id), key),
      name: (name && to_string(name)) || join_name(Map.get(form, :name), key),
      params: sub_map(form.params, key),
      data: sub_map(form.data, key),
      errors: errors_for(form_state, path),
      action: form.action,
      hidden: [],
      options: ProjectedForm.put_root_path(opts, path)
    }
  end

  defp join_name(nil, key), do: key
  defp join_name(parent, key), do: "#{parent}[#{key}]"

  defp join_id(nil, key), do: key
  defp join_id(parent, key), do: "#{parent}_#{key}"

  defp sub_map(container, key) do
    case container do
      %{^key => %{} = value} -> value
      _other -> %{}
    end
  end

  defp drop_collection_options!(opts) do
    Enum.reduce([:default, :prepend, :append], opts, fn key, opts ->
      case Keyword.fetch(opts, key) do
        {:ok, nil} -> Keyword.delete(opts, key)
        {:ok, value} -> raise_collection_option!(key, value)
        :error -> opts
      end
    end)
  end

  defp raise_collection_option!(key, value) do
    raise ArgumentError,
          "the #{inspect(key)} option is not supported: defaults come from Form " <>
            "state and collections arrive with Milestone B, got: #{inspect(value)}"
  end

  def input_value(form_state, form, field) do
    key = field_to_string(field)
    path = ProjectedForm.root_segments!(form) ++ [key]

    case Info.node_at(form_state.definition, path) do
      %Semantic.Field{} -> Form.field(form_state, path).display_value
      _other -> fallback_value(form, key)
    end
  end

  defp fallback_value(%{params: params, data: data}, key) do
    case params do
      %{^key => value} -> value
      %{} -> Map.get(data, key)
    end
  end

  def input_validations(form_state, form, field) do
    path = ProjectedForm.root_segments!(form) ++ [field_to_string(field)]

    case Info.node_at(form_state.definition, path) do
      %Semantic.Field{} = node -> validations(node)
      _other -> []
    end
  end

  # D-010: attributes derive from schema plus input policy, never from
  # `required` alone — a required string permitting "" gets no required
  # attribute, because "" is schema-valid there. The non-empty test
  # mirrors the compiler's :required_permits_empty exemption exactly.
  defp validations(%Semantic.Field{value_type: :string} = node) do
    required(node, nonempty_string?(node)) ++
      constraint(node, :min_length, :minlength) ++
      constraint(node, :max_length, :maxlength)
  end

  defp validations(%Semantic.Field{value_type: :boolean} = node) do
    required(node, true)
  end

  defp validations(%Semantic.Field{} = node) do
    required(node, true) ++
      constraint(node, :min, :min) ++
      constraint(node, :max, :max) ++
      step(node.value_type)
  end

  defp required(%Semantic.Field{required?: true}, true), do: [required: true]
  defp required(_node, _empty_input_forbidden?), do: []

  defp nonempty_string?(node) do
    Map.get(node.constraints, :min_length, 0) >= 1 or
      (is_list(node.options) and "" not in node.options)
  end

  defp constraint(node, key, attr) do
    case Map.fetch(node.constraints, key) do
      {:ok, value} -> [{attr, value}]
      :error -> []
    end
  end

  defp step(:integer), do: [step: 1]
  defp step(:number), do: [step: "any"]

  defp field_to_string(field) when is_atom(field), do: Atom.to_string(field)
  defp field_to_string(field) when is_binary(field), do: field

  defp reject_owned_option!(opts, key) do
    if Keyword.has_key?(opts, key) do
      raise ArgumentError,
            "the #{inspect(key)} option is owned by Formentation.Form state; " <>
              "drive it through Formentation.Form.transition/2 instead"
    end
  end

  # Spec §4: only direct scalar children of this object, the complete set
  # once an action exists — per-field visibility belongs to the source's
  # Formentation.Phoenix.StateView (D-027; for Formentation.Form that
  # never answers :default, so the projector never falls back to
  # used_input?/1), folded once into show_errors? by the projector;
  # themes only read that flag, never used_input?/1 or Form.show_issues?/2
  # directly. This projection decides no visibility itself. Object-level
  # and root issues stay out of Phoenix's per-field convention; themes
  # read them via the projector's plan.summary.
  defp errors_for(%Form{action: nil}, _object_path), do: []

  defp errors_for(%Form{} = form_state, object_path) do
    depth = length(object_path) + 1

    form_state.issues
    |> Enum.filter(fn {path, _issues} -> field_child?(form_state, path, object_path, depth) end)
    |> Enum.sort_by(fn {path, _issues} -> path.segments end)
    |> Enum.flat_map(fn {path, issues} ->
      key = error_key(List.last(path.segments))
      for issue <- issues, do: {key, {issue.message, code: issue.code, source: issue.source}}
    end)
  end

  # Only direct scalar children project into Phoenix's per-field errors:
  # an issue whose path names a group node (a missing required nested
  # object, for example) is object-level and stays out — it reaches a
  # theme through the projector's plan.summary, which sources non-field
  # entries from StateView.issues/2 (D-027) rather than from this module.
  # NOTE: this match must grow with any future scalar/leaf node kind —
  # a leaf kind missing here has its errors silently dropped.
  defp field_child?(form_state, path, object_path, depth) do
    length(path.segments) == depth and
      Enum.take(path.segments, depth - 1) == object_path and
      Info.semantic_kind(form_state.definition, path.segments) == :field
  end

  # Spec decision 4: phoenix_html matches error keys against the field
  # exactly as passed, and core components pass atom literals — so keys
  # must be atoms where the atom exists. to_existing_atom never creates
  # one; when it does not exist, no caller can be holding it to look up
  # with, and the string key loses nothing.
  # Consequence: when the atom exists, errors key by atom, so
  # form["name"].errors is [] while form[:name].errors matches —
  # the same asymmetry phoenix_ecto has.
  defp error_key(name) do
    String.to_existing_atom(name)
  rescue
    ArgumentError -> name
  end
end
