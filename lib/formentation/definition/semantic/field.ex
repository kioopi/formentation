defmodule Formentation.Definition.Semantic.Field do
  @moduledoc """
  Native semantic scalar field occurrence.

  This struct intentionally contains no presentation label, help, widget,
  hidden, or group-containment facts. A `nil` name is reserved for a
  collection item-template position.
  """

  alias Formentation.{NodeId, Origin, TemplatePath}

  @enforce_keys [:id, :name, :template_path, :value_type]
  defstruct [
    :id,
    :name,
    :role,
    :value_type,
    :template_path,
    :options,
    :default,
    :examples,
    required?: false,
    read_only?: false,
    constraints: %{},
    origins: []
  ]

  @doc false
  @spec new(String.t() | nil, TemplatePath.t(), value_type(), keyword()) :: t()
  def new(name, %TemplatePath{} = template_path, value_type, opts \\ [])
      when (is_binary(name) or is_nil(name)) and
             value_type in [:string, :integer, :number, :boolean] do
    %__MODULE__{
      id: Keyword.get(opts, :id, NodeId.from_path(template_path)),
      name: name,
      role: Keyword.get(opts, :role),
      value_type: value_type,
      template_path: template_path,
      options: Keyword.get(opts, :options),
      default: Keyword.get(opts, :default),
      examples: Keyword.get(opts, :examples),
      required?: Keyword.get(opts, :required?, false),
      read_only?: Keyword.get(opts, :read_only?, false),
      constraints: Keyword.get(opts, :constraints, %{}),
      origins: Keyword.get(opts, :origins, [])
    }
  end

  @typedoc """
  The source-neutral normalized scalar type of a field.

  It is orthogonal to the resolved abstract widget: `:integer` and `:number`
  share `:number_input` (D-038).
  """
  @type value_type :: :string | :integer | :number | :boolean

  @typedoc "A scalar option value retained from a source declaration."
  @type option :: String.t() | number() | boolean()

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t() | nil,
          role: atom() | nil,
          value_type: value_type(),
          template_path: TemplatePath.t(),
          options: [option()] | nil,
          default: term() | nil,
          examples: [term()] | nil,
          required?: boolean(),
          read_only?: boolean(),
          constraints: map(),
          origins: [{atom(), Origin.t()}]
        }
end
