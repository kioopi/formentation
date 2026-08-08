defmodule Formentation.ValidationPlan do
  @moduledoc """
  Executable identity plus an opaque, implementation-owned validation
  artifact.

  `module` implements `Formentation.Validation` and is the sole
  interpreter of `artifact`; core stores the pair verbatim and never
  inspects the artifact. A definition carries exactly zero (`nil`) or
  one plan.

      iex> plan = %Formentation.ValidationPlan{
      ...>   module: Formentation.Definition.Source.JSONSchema.Validator,
      ...>   artifact: {:opaque, 1}
      ...> }
      iex> {plan.module, plan.artifact}
      {Formentation.Definition.Source.JSONSchema.Validator, {:opaque, 1}}
  """

  @enforce_keys [:module, :artifact]
  defstruct [:module, :artifact]

  @type t :: %__MODULE__{
          module: module(),
          artifact: term()
        }
end
