defimpl Formentation.Phoenix.StateView, for: Any do
  @moduledoc """
  The conservative default for any `Phoenix.HTML.FormData` source without
  a dedicated state view.

  Preserves exactly the behaviour the projector had before D-027: `:submit`
  is the only action that counts as submitted, visibility is left to the
  Phoenix default, and root/object issue enrichment is reported as
  unavailable rather than guessed. Projection never crashes merely because
  a source has no implementation.
  """

  def submitted?(_source, %Phoenix.HTML.Form{action: action}), do: action == :submit

  def issue_visibility(_source, _form, _instance_path), do: :default

  def issues(_source, _form), do: :unavailable
end
