defmodule Formentation.Source do
  @moduledoc """
  Contract for declaration source adapters (D-004). An adapter translates
  source vocabulary into a compiled definition while stamping origins.

  A shared normalized compiler-input format is deliberately deferred until
  the JSON Schema adapter (slice 2) shows what it must contain.
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
