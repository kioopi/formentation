defmodule Formentation.Semantic.Index do
  @moduledoc false

  alias Formentation.TemplatePath

  defstruct by_id: %{}, by_template_path: %{}

  @type kind :: :object | :field | :unsupported
  @type entry :: %{kind: kind(), node: term()}

  @type t :: %__MODULE__{
          by_id: %{String.t() => entry()},
          by_template_path: %{TemplatePath.t() => entry()}
        }
end
