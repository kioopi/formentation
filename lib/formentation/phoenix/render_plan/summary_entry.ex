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
end
