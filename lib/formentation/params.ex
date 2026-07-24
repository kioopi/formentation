defmodule Formentation.Params do
  @moduledoc """
  The explicit transition envelope (D-013): values plus mode, scope, and
  event. A bare params map is ambiguous — an absent key could mean
  "cleared" or "untouched" — so `Formentation.Form.transition/2` refuses
  to accept one. `:patch` mode and non-root scope are reserved shapes:
  present in the struct, rejected until a real producer exists (the first
  candidate is an input-level `phx-change`; expiry recorded in D-013).

  `event: :submit` is what gates group- and root-level issue visibility
  in `Formentation.Form.show_issues?/2` (D-014).
  """

  alias Formentation.InstancePath

  @enforce_keys [:values]
  defstruct [:values, mode: :replace, scope: [], event: :change]

  @type t :: %__MODULE__{
          values: map(),
          mode: :replace | :patch,
          scope: [InstancePath.segment()],
          event: :change | :submit
        }
end
