defmodule Formentation.Definition.Validation do
  @moduledoc """
  Source-neutral contract for authoritative validation of a decoded form
  instance.

  Implementations own the validation artifact they receive and translate
  the violations it reports into complete `Formentation.Issue` values
  (`InstancePath`, code, message, and `source: :validation`). Returning
  `[]` means the candidate is valid. Invalid input is reported as issues,
  never raised: an exception from `validate/2` is treated as an
  integration defect and propagates — core does not rescue it into an
  issue.

  This contract belongs to core; implementations belong to integrations
  (for example `Formentation.Definition.Source.JSONSchema.Validator`). It concerns only
  runtime candidate validation — declaration/metaschema checking produces
  `Formentation.Diagnostic` values and is not part of this behaviour.
  """

  alias Formentation.Issue

  @callback validate(artifact :: term(), instance :: map()) :: [Issue.t()]
end
