defmodule Formentation.Issue do
  @moduledoc """
  A problem with a submitted instance: a value that failed decoding
  (`source: :decode`) or an authoritative-validation failure
  (`source: :validation`). `source` distinguishes transport/decode
  failures from candidate-validation failures; the integration that
  produced a validation issue (e.g. JSON Schema) is identified by its
  `code`/`message`, never by the core vocabulary. Distinct from a
  compile-time `Formentation.Diagnostic`, which concerns declaration
  processing.
  """

  alias Formentation.InstancePath

  @enforce_keys [:path, :code, :message, :source]
  defstruct [:path, :code, :message, :source]

  @type t :: %__MODULE__{
          path: InstancePath.t(),
          code: atom(),
          message: String.t(),
          source: :decode | :validation
        }
end
