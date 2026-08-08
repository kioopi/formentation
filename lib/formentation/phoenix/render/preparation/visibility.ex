defmodule Formentation.Phoenix.Render.Preparation.Visibility do
  @moduledoc """
  The D-014/D-027 visibility and submission policy: whether a field's errors
  show, and whether the form counts as submitted.

  Not part of the public API — reached only through `Render.Preparation.prepare/2`
  and `prepare_at/3` while projecting a `Presentation.Field`. Kept out of the
  published docs by `mix.exs`, but documented here because "does this issue
  show" is a self-contained question worth understanding on its own: the
  source's `StateView` decides first, and only a `:default` answer falls back
  to the Phoenix-generic rule — `submitted?/1` or `Phoenix.Component.used_input?/1`.
  This is the only module that calls `used_input?/1`.
  """

  alias Formentation.InstancePath
  alias Formentation.Phoenix.StateView

  @typedoc """
  The slice of `Render.Preparation`'s projection context this module reads.
  Deliberately narrower than the full context passed around during
  projection — visibility decisions work only from the source's `StateView`
  and the root form, never from namespace/traversal state.
  """
  @type ctx :: %{source: StateView.t(), root_form: Phoenix.HTML.Form.t()}

  @doc """
  Decides whether `field`'s errors should show.

  The source's `StateView.issue_visibility/3` decides first (D-027); only a
  `:default` answer falls back to the Phoenix-compatible default: submitted,
  or `Phoenix.Component.used_input?/1` (D-014).

  ## Example

      iex> form = Phoenix.HTML.FormData.to_form(%{"email" => ""}, as: "payload", errors: [email: {"can't be blank", []}])
      iex> field = form[:email]
      iex> ctx = %{source: form.source, root_form: form}
      iex> Formentation.Phoenix.Render.Preparation.Visibility.show_errors?(field, ctx, ["email"])
      true
  """
  @spec show_errors?(Phoenix.HTML.FormField.t(), ctx(), [InstancePath.segment()]) :: boolean()
  def show_errors?(field, ctx, path) do
    field.errors != [] and
      visible?(ctx, path, fn -> submitted?(ctx) or Phoenix.Component.used_input?(field) end)
  end

  @doc """
  Whether the source's `StateView` considers the form submitted.
  """
  @spec submitted?(ctx()) :: boolean()
  def submitted?(ctx), do: StateView.submitted?(ctx.source, ctx.root_form)

  # Resolves a path's visibility through the source's `StateView`, falling back
  # to `default_fun.()` when it answers `:default`.
  @spec visible?(ctx(), [InstancePath.segment()], (-> boolean())) :: boolean()
  defp visible?(ctx, path, default_fun) do
    case StateView.issue_visibility(ctx.source, ctx.root_form, InstancePath.new!(path)) do
      :show -> true
      :hide -> false
      :default -> default_fun.()
    end
  end
end
