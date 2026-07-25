defmodule Formentation.SourceFixture do
  @moduledoc """
  A minimal non-Formentation `Phoenix.HTML.FormData` source with canned
  `Formentation.Phoenix.StateView` answers, used to prove the state-view
  contract is genuinely source-neutral (spec §6).

  Deliberately small: flat scalar params, a fixed error list, and stored
  answers for each callback. It uses `:commit` rather than `:submit` in
  tests to prove submission is semantic. It is a contract proof, not a
  prototype Ecto or Ash adapter, and models no nesting.
  """

  alias Formentation.InstancePath
  alias Formentation.Phoenix.StateView

  defstruct params: %{},
            errors: [],
            action: nil,
            submitted?: false,
            visibility: %{},
            issues: :unavailable

  @type t :: %__MODULE__{
          params: %{String.t() => term()},
          errors: keyword(),
          action: atom(),
          submitted?: boolean(),
          visibility: %{[InstancePath.segment()] => :default | :show | :hide},
          issues: :unavailable | {:ok, [StateView.Issue.t()]}
        }
end

defimpl Phoenix.HTML.FormData, for: Formentation.SourceFixture do
  def to_form(source, opts) do
    {name, opts} = Keyword.pop(opts, :as)
    name = name && to_string(name)

    %Phoenix.HTML.Form{
      source: source,
      impl: __MODULE__,
      id: name,
      name: name,
      params: source.params,
      data: %{},
      errors: source.errors,
      action: source.action,
      hidden: [],
      options: opts
    }
  end

  def to_form(_source, _form, field, _opts) do
    raise ArgumentError,
          "Formentation.SourceFixture declares no nested objects, got: #{inspect(field)}"
  end

  def input_value(source, _form, field), do: Map.get(source.params, to_string(field))

  def input_validations(_source, _form, _field), do: []
end

defimpl Formentation.Phoenix.StateView, for: Formentation.SourceFixture do
  alias Formentation.InstancePath

  def submitted?(source, _form), do: source.submitted?

  def issue_visibility(source, _form, %InstancePath{segments: segments}) do
    Map.get(source.visibility, segments, :default)
  end

  def issues(source, _form), do: source.issues
end
