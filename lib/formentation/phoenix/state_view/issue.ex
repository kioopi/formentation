defmodule Formentation.Phoenix.StateView.Issue do
  @moduledoc """
  The only issue shape projection needs from a state view: an absolute
  instance path and an already-displayable message.

  Deliberately not `Formentation.Issue`. External sources own their error
  representations and must not be forced to manufacture core structs, and
  a state view may synthesize an explanation that is not an ordinary core
  issue at all. The backing source's richer error object stays
  authoritative; this is a projection-facing normalization.
  """

  alias Formentation.InstancePath

  @enforce_keys [:path, :message]
  defstruct [:path, :message]

  @type t :: %__MODULE__{
          path: InstancePath.t(),
          message: String.t()
        }
end
