defmodule Formentation.Fixture do
  @moduledoc """
  Contract every differential fixture implements: one form declared
  through each declaration source (D-004), so tests can compile the same
  fixture via `Formentation.Source.Map` and `Formentation.JSONSchema`
  and compare the results fact by fact.
  """

  @doc "Declaration for the plain Elixir map source."
  @callback map_source() :: map()

  @doc "The same declaration as a decoded JSON Schema document."
  @callback json_schema() :: map()

  @doc "UI hints accompanying the JSON Schema declaration."
  @callback ui_hints() :: map()

  @doc "Names of the scalar fields tests iterate over."
  @callback field_names() :: [String.t()]
end
