defmodule Formentation.Source do
  @moduledoc """
  Contract for declaration source adapters (D-004). An adapter translates
  source vocabulary into a compiled definition while stamping origins.

  A shared normalized compiler-input format is deliberately deferred until
  the JSON Schema adapter (slice 2) shows what it must contain.

  ## Compatibility

  This behaviour is published so the contract the built-in adapters
  satisfy is readable, and `Formentation.compile/2` and
  `Formentation.form/2` will keep accepting any module that exports
  `compile/2`. That dispatch mechanism is stable.

  Writing your own adapter is a different matter. The internals required
  to construct a valid `Formentation.Definition` are not yet a
  compatibility-stable surface, so an out-of-tree adapter may break
  across versions. Documented here does not mean stable to build against.
  """

  alias Formentation.{Definition, Diagnostic}

  @doc """
  Compiles one source declaration into a definition. Warnings ride the
  `{:ok, ...}` diagnostics list; errors fail the whole compile. Adapters
  must return string names and never create atoms from declaration
  input.
  """
  @callback compile(source :: term(), opts :: keyword()) ::
              {:ok, Definition.t(), [Diagnostic.t()]} | {:error, [Diagnostic.t()]}
end
