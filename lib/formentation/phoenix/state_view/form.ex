defimpl Formentation.Phoenix.StateView, for: Formentation.Form do
  @moduledoc """
  The complete state view for Formentation's own runtime state.

  Lives in the Phoenix layer, not core: core must stay Phoenix-free, and
  this module names `%Phoenix.HTML.Form{}` in its callbacks. It reads
  `Formentation.Form` only through that module's public queries.
  """

  alias Formentation.{Form, InstancePath}
  alias Formentation.Phoenix.StateView

  def submitted?(form_state, _form), do: Form.submitted?(form_state)

  # Never :default — Formentation.Form owns the complete D-014 policy
  # (scalar issues on submit or once used; group and root issues on
  # submit only), so deferring to the projector's approximation could
  # only reintroduce a second, drifting copy of that rule.
  def issue_visibility(form_state, _form, %InstancePath{segments: segments}) do
    if Form.show_issues?(form_state, segments), do: :show, else: :hide
  end

  # Sorting by segments gives a deterministic cross-path order; Enum.sort_by
  # is stable, so issues sharing a path keep the order Form recorded them in.
  def issues(form_state, _form) do
    normalized =
      form_state
      |> Form.issues()
      |> Enum.sort_by(& &1.path.segments)
      |> Enum.map(&%StateView.Issue{path: &1.path, message: &1.message})

    {:ok, normalized}
  end
end
