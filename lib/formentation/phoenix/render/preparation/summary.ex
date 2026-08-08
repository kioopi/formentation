defmodule Formentation.Phoenix.Render.Preparation.Summary do
  @moduledoc """
  Builds a `Render.Plan`'s submit-gated error summary from a prepared render
  tree plus the projection context `Render.Preparation` resolved for it.

  Not part of the public API — reached only through `Render.Preparation.prepare/2`'s
  `plan.summary`. Kept out of the published docs by `mix.exs`, but documented
  here because it is one of the two summary-entry sources worth understanding
  together: field-level entries are read off the already-prepared `Render.Node`
  tree, and root/object/unsupported-node entries are read from `StateView.issues/2`,
  since those never enter Phoenix's per-field error convention.

  An object-level issue links to its rendered fieldset when one exists (#34):
  `object_targets/1` indexes every `:object` group in `root.children` by its
  `occurrence_path`, and a non-field issue whose path matches links to that
  group's `dom.container`, labelled with its `legend`. `root` itself is never
  indexed — `fields/1` never renders the projection root's own fieldset,
  native or nested — so a root-of-form or nested-projection-root issue always
  stays unlinked, and a `:presentation_group` is never a link target since it
  owns no semantic occurrence.
  """

  alias Formentation.{Definition, Info, InstancePath}
  alias Formentation.Phoenix.Render.{Node, Plan}
  alias Formentation.Phoenix.Render.Preparation.Visibility
  alias Formentation.Phoenix.StateView

  @typedoc """
  The slice of `Render.Preparation`'s projection context this module reads.
  Deliberately narrower than the full context passed around during
  projection (which also carries `path`, `root_path`, `semantic_nodes` and
  `dom_namespace`) — summary construction works only from the already-prepared
  render tree and the source's `StateView`, never from namespace/traversal
  state, so those fields have no way in here. The projection root reaches
  here as `root_instance_path`, the form the `InstancePath` comparisons in
  `inside_projection?/2` need; the raw `root_path` segments do not.
  """
  @type ctx :: %{
          source: StateView.t(),
          root_form: Phoenix.HTML.Form.t(),
          root_instance_path: InstancePath.t(),
          definition: Definition.t()
        }

  @doc """
  Returns the summary entries for `root`, or `[]` when `ctx` is not submitted.

  `root` is the `Render.Node.Group` `Render.Preparation` just finished
  projecting. Entry order is: field entries in tree order, then non-field
  entries in the state view's authoritative order.
  """
  @spec build(Node.Group.t(), ctx()) :: [Plan.SummaryEntry.t()]
  def build(root, ctx) do
    if Visibility.submitted?(%{source: ctx.source, root_form: ctx.root_form}) do
      field_entries(root) ++ non_field_entries(root, ctx)
    else
      []
    end
  end

  defp field_entries(%Node.Group{children: children}) do
    Enum.flat_map(children, &field_entries/1)
  end

  # Hidden inputs have no visible, focusable target in the reference theme, so
  # their errors cannot be actionable summary entries.
  defp field_entries(%Node.Field{widget: :hidden_input}), do: []

  defp field_entries(%Node.Field{show_errors?: true} = node) do
    target = %{id: summary_target(node), label: node.label}

    for {message, _opts} <- node.errors do
      Plan.SummaryEntry.from_target(target, message)
    end
  end

  defp field_entries(%Node.Field{}), do: []

  defp summary_target(%Node.Field{widget: widget, dom: dom}),
    do: Map.fetch!(dom, summary_part(widget))

  # Reference-theme contract: every widget must appear here. Composite widgets
  # target the element their component renders as the group-level control;
  # scalar widgets target their control.
  defp summary_part(:radio_group), do: :container

  defp summary_part(widget)
       when widget in [
              :checkbox,
              :textarea,
              :select,
              :number_input,
              :date_input,
              :email_input,
              :url_input,
              :text_input
            ],
       do: :control

  defp non_field_entries(root, ctx) do
    case StateView.issues(ctx.source, ctx.root_form) do
      :unavailable ->
        []

      {:ok, issues} ->
        targets = object_targets(root)

        issues
        |> Enum.filter(&(inside_projection?(ctx, &1) and non_field_visible?(ctx, &1)))
        |> Enum.map(&non_field_entry(&1, ctx, targets))
    end
  end

  defp non_field_entry(%StateView.Issue{path: path, message: message}, ctx, targets) do
    case Map.fetch(targets, path) do
      {:ok, target} ->
        Plan.SummaryEntry.from_target(target, message)

      :error ->
        Plan.SummaryEntry.from_target(%{id: nil, label: summary_label(ctx, path)}, message)
    end
  end

  # Indexes every rendered `:object` group under `root` (never `root` itself
  # — see moduledoc) by its exact occurrence path, so `non_field_entry/3` can
  # look a matching issue's target up directly instead of reconstructing a
  # DOM id from the issue's path. A `:presentation_group` is skipped but its
  # children are still walked, since a semantic object can render inside a
  # presentation-only wrapper.
  defp object_targets(%Node.Group{children: children}) do
    Enum.reduce(children, %{}, &index_object_target/2)
  end

  defp index_object_target(%Node.Field{}, index), do: index

  defp index_object_target(%Node.Group{kind: :presentation_group} = group, index) do
    Enum.reduce(group.children, index, &index_object_target/2)
  end

  defp index_object_target(%Node.Group{kind: :object} = group, index) do
    target = %{id: group.dom.container, label: group.legend}

    index
    |> put_object_target(group.occurrence_path, target)
    |> then(fn index -> Enum.reduce(group.children, index, &index_object_target/2) end)
  end

  # D-033 guarantees each supported occurrence renders exactly once, so two
  # `:object` groups claiming the same path is an internal invariant failure,
  # not a case for the theme or a source to trigger.
  defp put_object_target(index, path, target) do
    if Map.has_key?(index, path) do
      invariant!("two rendered object groups claim the same occurrence #{inspect(path)}")
    end

    Map.put(index, path, target)
  end

  defp invariant!(message), do: raise(ArgumentError, "invalid prepared tree: " <> message)

  # Unlike show_errors?/3 (used for fields), :default counts as visible here:
  # non_field_entries/1 only runs from build/2 once submitted?(ctx) is
  # already true, so the submission gate is already applied and there is
  # no per-entry Phoenix default left to apply — only an explicit :hide
  # suppresses an entry.
  defp non_field_visible?(ctx, %StateView.Issue{path: path}) do
    not field_path?(ctx, path) and
      StateView.issue_visibility(ctx.source, ctx.root_form, path) != :hide
  end

  defp field_path?(ctx, %InstancePath{segments: segments}) do
    Info.semantic_kind(ctx.definition, segments) == :field
  end

  # D-028's shared predicate, not a second implementation of it: "is this
  # path under that path" is decided segment-wise in one place, so
  # ["tag"] never counts as an ancestor of ["tags"].
  #
  # Nuance worth knowing before someone reports it as a bug: an object-level
  # issue at the projection root *itself* passes this filter and then gets
  # summary_label/2 == nil, because Info.semantic_kind/2 says :object. It
  # therefore renders as an unlabelled plain-text entry — visually identical
  # to a root-of-form issue. At root_path == [] that reading was exactly
  # right; at root_path == ["address"] it is slightly misleading, but not
  # enough to warrant a second label rule.
  defp inside_projection?(ctx, %StateView.Issue{path: path}) do
    InstancePath.ancestor_or_self?(ctx.root_instance_path, path)
  end

  # An unsupported node carries a name a reader can recognize, so its
  # entry is worth labelling; root and group issues stay unlabelled, as
  # they were before D-027.
  defp summary_label(ctx, %InstancePath{segments: segments}) do
    case Info.semantic_kind(ctx.definition, segments) do
      :unsupported -> humanize(List.last(segments))
      _root_object_or_unknown -> nil
    end
  end

  defp humanize(name) do
    name |> String.replace("_", " ") |> String.capitalize()
  end
end
