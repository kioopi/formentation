defmodule Formentation.Definition.Presentation do
  @moduledoc """
  Native presentation layout vocabulary.

  Presentation nodes carry layout identity and semantic references. They do not
  own semantic field facts such as type, role, requiredness, constraints, or
  decode participation.
  """

  alias Formentation.Definition.Presentation.{Field, Group, Object}

  @type descriptor :: Object.t() | Field.t() | Group.t()

  @doc false
  @spec object_id(String.t()) :: String.t()
  def object_id(semantic_id) when is_binary(semantic_id), do: "layout:object:" <> semantic_id

  @doc false
  @spec field_id(String.t()) :: String.t()
  def field_id(semantic_id) when is_binary(semantic_id), do: "layout:field:" <> semantic_id
end
