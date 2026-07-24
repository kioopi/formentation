defmodule Formentation.Issue do
  @moduledoc """
  A problem with a submitted instance: a value that failed decoding
  (`source: :decode`) or a schema violation (`source: :schema`). Distinct
  from a compile-time `Formentation.Diagnostic`, which concerns
  declaration processing.
  """

  alias Formentation.InstancePath

  @enforce_keys [:path, :code, :message, :source]
  defstruct [:path, :code, :message, :source]

  @type t :: %__MODULE__{
          path: InstancePath.t(),
          code: atom(),
          message: String.t(),
          source: :decode | :schema
        }
end
