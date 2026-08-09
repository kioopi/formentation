defprotocol Formentation.Phoenix.StateView do
  @moduledoc """
  The minimal read-only semantic facts projection needs beyond
  `%Phoenix.HTML.Form{}` (D-027).

  `%Phoenix.HTML.Form{}` remains the primary projection boundary: values,
  names, IDs, input validations, per-field errors, params behind
  `Phoenix.Component.used_input?/1`, and nested forms all keep coming from
  Phoenix. Three things cannot: whether an arbitrary action means
  *submitted*, whether a source owns a visibility policy Phoenix cannot
  infer, and root/object issues that deliberately stay out of Phoenix's
  per-field error convention.

  Dispatch is on `form.source`, so no adapter option appears on
  render preparation or on any component. Sources
  without an implementation fall back to `Any`, which reproduces the
  conservative Phoenix-generic behaviour.

  This is a projection/read-model boundary only. It owns no decoding, no
  validation, no mutation, no LiveView events, no branch transitions and
  no collection operations.

  Spec: docs/superpowers/specs/2026-07-25-runtime-state-view-contract-design.md
  """

  alias Formentation.InstancePath
  alias Formentation.Phoenix.StateView

  @fallback_to_any true

  @doc """
  Whether `source` considers this form submitted for projection policy.

  Means "the source's semantic submit state", not "`form.action` equals a
  particular atom" — an external source may use `:commit`, `:save`,
  `:insert` or `:update`.

      iex> form = Phoenix.HTML.FormData.to_form(%{"a" => "1"}, as: "payload")
      iex> {Formentation.Phoenix.StateView.submitted?(form.source, form),
      ...>  Formentation.Phoenix.StateView.submitted?(form.source, %{form | action: :submit})}
      {false, true}
  """
  @spec submitted?(t(), Phoenix.HTML.Form.t()) :: boolean()
  def submitted?(source, form)

  @doc """
  The source's visibility policy for issues at one absolute instance path.

  `:default` asks render preparation to apply its Phoenix-compatible default
  (submitted, or `Phoenix.Component.used_input?/1` for a scalar field);
  `:show` and `:hide` override it.

  Visibility never controls storage or enumeration — hidden issues stay
  present in the authoritative state and in `issues/2`. Only display is
  affected.

      iex> form = Phoenix.HTML.FormData.to_form(%{"a" => "1"}, as: "payload")
      iex> path = Formentation.InstancePath.new!(["a"])
      iex> Formentation.Phoenix.StateView.issue_visibility(form.source, form, path)
      :default
  """
  @spec issue_visibility(t(), Phoenix.HTML.Form.t(), InstancePath.t()) ::
          :default | :show | :hide
  def issue_visibility(source, form, instance_path)

  @doc """
  Every issue the source can locate, normalized for projection.

  `:unavailable` means the source has no complete enumeration capability;
  `{:ok, []}` means enumeration is supported and there is nothing to
  report. Returned order is the authoritative display order and must be
  deterministic — preparation preserves it after filtering.

  Scalar-field issues may appear here; preparation drops the ones whose
  path resolves to a `Formentation.Definition.Semantic.Field` because Phoenix already
  carries them as `field.errors`.

      iex> form = Phoenix.HTML.FormData.to_form(%{"a" => "1"}, as: "payload")
      iex> Formentation.Phoenix.StateView.issues(form.source, form)
      :unavailable
  """
  @spec issues(t(), Phoenix.HTML.Form.t()) :: :unavailable | {:ok, [StateView.Issue.t()]}
  def issues(source, form)
end
