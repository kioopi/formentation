defmodule Formentation.SourceFixture do
  @moduledoc """
  A minimal non-Formentation `Phoenix.HTML.FormData` source with canned
  `Formentation.Phoenix.StateView` answers, used to prove the state-view
  contract is genuinely source-neutral (spec §6).

  Deliberately small: scalar params, a fixed error list, and stored
  answers for each callback. It uses `:commit` rather than `:submit` in
  tests to prove submission is semantic. It is a contract proof, not a
  prototype Ecto or Ash adapter.

  Nesting is content-derived: a params entry holding a map is a nested
  object, and `to_form/4` scopes a fresh fixture to it. That is enough
  to prove a group-level issue reaches the summary through
  `Formentation.Phoenix.StateView.issues/2` alone — the nested source
  carries no state-view answers of its own, and needs none, because the
  render preparation always dispatches on the root source.
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

  def to_form(source, form, field, opts) do
    key = to_string(field)

    case Map.get(source.params, key) do
      %{} = params -> [nested_form(form, key, params, opts)]
      _absent_or_scalar -> raise_not_nested!(field)
    end
  end

  defp nested_form(form, key, params, opts) do
    %Phoenix.HTML.Form{
      source: %Formentation.SourceFixture{params: params},
      impl: __MODULE__,
      id: join_id(form.id, key),
      name: join_name(form.name, key),
      params: params,
      data: %{},
      errors: [],
      action: form.action,
      hidden: [],
      options: opts
    }
  end

  defp join_id(nil, key), do: key
  defp join_id(parent, key), do: "#{parent}_#{key}"

  defp join_name(nil, key), do: key
  defp join_name(parent, key), do: "#{parent}[#{key}]"

  defp raise_not_nested!(field) do
    raise ArgumentError,
          "Formentation.SourceFixture nests only where its params hold a map, " <>
            "got: #{inspect(field)}"
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
