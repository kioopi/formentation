defmodule Formentation.Occurrence do
  @moduledoc """
  Binds static template nodes to their concrete runtime occurrences.

  A `Formentation.TemplatePath` names one declared node; a
  `Formentation.InstancePath` names one occurrence of that node in a
  concrete data instance. Without collections the two are 1:1; a
  collection template node has one occurrence per item in the data.
  This module owns that binding: enumeration is a function of the
  definition *and* the data, because only the data can say how many
  occurrences a collection node has.

  What this binds is *location*: which instance path a template node
  occupies. It is not stable item identity — the question of what makes
  an item "the same item" across add, remove, and reorder is open, and
  may need form-owned state rather than a function of the definition and
  the data alone. In Milestone A the binding is the trivial 1:1
  projection and `data` goes unused; Milestone B may change this
  module's signature, not only its internals, which is why it is
  internal and kept out of the published docs.
  """

  alias Formentation.{Definition, InstancePath}
  alias Formentation.Definition.Semantic

  @typedoc false
  @type binding :: {Semantic.Entry.t(), InstancePath.t()}

  @doc """
  Every semantic node paired with its concrete instance path, in
  declaration order, root first.

  ## Example

      iex> {:ok, definition, []} =
      ...>   Formentation.compile(
      ...>     %{kind: :object, properties: [{"name", %{kind: :string}}]},
      ...>     adapter: Formentation.Source.Map
      ...>   )
      iex> Formentation.Occurrence.occurrences(definition, %{})
      ...> |> Enum.map(fn {entry, path} -> {entry.kind, path.segments} end)
      [{:object, []}, {:field, ["name"]}]
  """
  @spec occurrences(Definition.t(), map()) :: [binding()]
  def occurrences(%Definition{} = definition, data) when is_map(data) do
    definition
    |> Semantic.root()
    |> bind(InstancePath.new!([]))
  end

  defp bind(%Semantic.Entry{} = entry, %InstancePath{} = path) do
    [
      {entry, path}
      | entry
        |> Semantic.direct_children()
        |> Enum.flat_map(&bind(&1, InstancePath.child(path, &1.name)))
    ]
  end
end
