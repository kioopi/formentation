defmodule Formentation.Phoenix.RenderPreparation.Summary do
  @moduledoc """
  Builds a `RenderPlan`'s submit-gated error summary from a prepared render
  tree plus the projection context `RenderPreparation` resolved for it.

  Not part of the public API — reached only through `RenderPreparation.prepare/2`'s
  `plan.summary`. Kept out of the published docs by `mix.exs`, but documented
  here because it is one of the two summary-entry sources worth understanding
  together: field-level entries are read off the already-prepared `RenderNode`
  tree, and root/object/unsupported-node entries are read from `StateView.issues/2`,
  since those never enter Phoenix's per-field error convention.
  """

  alias Formentation.{Info, InstancePath}
  alias Formentation.Phoenix.{RenderNode, RenderPlan, StateView}

  @doc """
  Returns the summary entries for `root`, or `[]` when `ctx` is not submitted.

  `root` is the `RenderNode.Group` `RenderPreparation` just finished
  projecting; `ctx` is the same projection context passed throughout
  `RenderPreparation` (only `source`, `root_form`, `root_instance_path` and
  `definition` are read here). Entry order is: field entries in tree order,
  then non-field entries in the state view's authoritative order.
  """
  @spec build(RenderNode.Group.t(), map()) :: [Formentation.Phoenix.RenderPlan.SummaryEntry.t()]
  def build(root, ctx) do
    if submitted?(ctx) do
      field_entries(root) ++ non_field_entries(ctx)
    else
      []
    end
  end

  defp submitted?(ctx), do: StateView.submitted?(ctx.source, ctx.root_form)

  defp field_entries(%RenderNode.Group{children: children}) do
    Enum.flat_map(children, &field_entries/1)
  end

  # Hidden inputs have no visible, focusable target in the reference theme, so
  # their errors cannot be actionable summary entries.
  defp field_entries(%RenderNode.Field{widget: :hidden_input}), do: []

  defp field_entries(%RenderNode.Field{show_errors?: true} = node) do
    for {message, _opts} <- node.errors do
      summary_entry(summary_target(node), node.label, message)
    end
  end

  defp field_entries(%RenderNode.Field{}), do: []

  defp summary_target(%RenderNode.Field{widget: widget, dom: dom}),
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

  defp non_field_entries(ctx) do
    case StateView.issues(ctx.source, ctx.root_form) do
      :unavailable ->
        []

      {:ok, issues} ->
        issues
        |> Enum.filter(&(inside_projection?(ctx, &1) and non_field_visible?(ctx, &1)))
        |> Enum.map(&summary_entry(nil, summary_label(ctx, &1.path), &1.message))
    end
  end

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

  defp summary_entry(id, label, message),
    do: %RenderPlan.SummaryEntry{id: id, label: label, message: message}

  defp humanize(name) do
    name |> String.replace("_", " ") |> String.capitalize()
  end
end
