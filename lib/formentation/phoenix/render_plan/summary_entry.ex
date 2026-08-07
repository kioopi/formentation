defmodule Formentation.Phoenix.RenderPlan.SummaryEntry do
  @moduledoc """
  One entry in a `RenderPlan`'s error summary.

  `id` is the DOM id of the entry's link target, or `nil` for an unlinked
  plain-text entry (a root/object issue with no rendered target, or an
  issue the reference theme cannot address). `label` is `nil` whenever the
  entry has no meaningful prefix of its own — the message stands alone.
  """

  @enforce_keys [:message]
  defstruct [:id, :label, :message]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          label: String.t() | nil,
          message: String.t()
        }

  @type target :: %{id: String.t() | nil, label: String.t() | nil}

  @doc """
  Builds an entry from a summary target and a message.

  `target` carries the two facts every entry source resolves before it can
  build one: the DOM id to link to (`nil` when there is none) and the label
  to prefix the message with (`nil` when the message stands alone). A
  field resolves both from its prepared `RenderNode.Field`; a root or
  unsupported-node issue resolves only `label`, or neither.

      iex> Formentation.Phoenix.RenderPlan.SummaryEntry.from_target(%{id: nil, label: nil}, "is invalid")
      %Formentation.Phoenix.RenderPlan.SummaryEntry{id: nil, label: nil, message: "is invalid"}

      iex> Formentation.Phoenix.RenderPlan.SummaryEntry.from_target(%{id: "email", label: "Email"}, "is required")
      %Formentation.Phoenix.RenderPlan.SummaryEntry{id: "email", label: "Email", message: "is required"}
  """
  @spec from_target(target(), String.t()) :: t()
  def from_target(%{id: id, label: label}, message) do
    %__MODULE__{id: id, label: label, message: message}
  end
end
