defimpl Formentation.Phoenix.StateView, for: Formentation.Form do
  @moduledoc """
  The complete state view for Formentation's own runtime state.

  Lives in the Phoenix layer, not core: core must stay Phoenix-free, and
  this module names `%Phoenix.HTML.Form{}` in its callbacks. It reads
  `Formentation.Form` only through that module's public queries.
  """

  alias Formentation.{Form, InstancePath}
  alias Formentation.Form.SubmissionBlocker
  alias Formentation.Phoenix.StateView

  def submitted?(form_state, _form), do: Form.submitted?(form_state)

  # Never :default — Formentation.Form owns the complete D-014 policy
  # (scalar issues on submit or once used; group and root issues on
  # submit only), so deferring to the projector's approximation could
  # only reintroduce a second, drifting copy of that rule.
  def issue_visibility(form_state, _form, %InstancePath{segments: segments}) do
    if Form.show_issues?(form_state, segments), do: :show, else: :hide
  end

  # Blockers first, in Info's declaration order, then everything else
  # sorted by segments for a deterministic cross-path order; Enum.sort_by
  # is stable, so issues sharing a path keep the order Form recorded them
  # in. Blockers lead because a form that cannot repair a value at all is
  # the more urgent thing to read (D-028).
  def issues(form_state, _form) do
    blockers = Form.submission_blockers(form_state)
    {:ok, Enum.map(blockers, &blocker_issue/1) ++ unowned_issues(form_state, blockers)}
  end

  # The capability explanation is built here, not in the projector: it is
  # this source's account of its own limits, and a source with different
  # semantics owes projection nothing but a displayable message.
  defp blocker_issue(%SubmissionBlocker{path: path} = blocker) do
    %StateView.Issue{path: path, message: blocker_message(blocker)}
  end

  defp blocker_message(%SubmissionBlocker{issues: [], message: message}), do: message

  defp blocker_message(%SubmissionBlocker{issues: issues, message: message}) do
    message <> " Validation: " <> Enum.map_join(issues, "; ", & &1.message)
  end

  # An issue a blocker already speaks for would otherwise be displayed
  # twice — once inside the explanation, once as a bare line whose repair
  # the form cannot offer. Rejected by identity, not by path: ownership
  # reaches below the unsupported node, and unrelated issues at those
  # paths must not be swept up with it.
  defp unowned_issues(form_state, blockers) do
    owned = blockers |> Enum.flat_map(& &1.issues) |> MapSet.new()

    form_state
    |> Form.issues()
    |> Enum.reject(&MapSet.member?(owned, &1))
    |> Enum.sort_by(& &1.path.segments)
    |> Enum.map(&%StateView.Issue{path: &1.path, message: &1.message})
  end
end
