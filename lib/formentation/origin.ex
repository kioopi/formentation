defmodule Formentation.Origin do
  @moduledoc """
  Provenance tags for compiled definition facts.

  Origins identify which source vocabulary contributed a fact and where in that
  source it came from.
  """

  @type t ::
          {:map_source, [atom() | String.t()]}
          | {:json_schema, String.t()}
          | {:ui_hints, String.t()}
          | {:inference, atom()}
end
