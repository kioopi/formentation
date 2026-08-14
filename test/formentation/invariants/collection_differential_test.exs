defmodule Formentation.CollectionDifferentialTest do
  use ExUnit.Case, async: true

  alias Formentation.Definition.Semantic
  alias Formentation.Fixtures.{Addresses, Measurements}
  alias Formentation.Info

  # The same fact set as the main differential test; collections
  # additionally carry :constraints (Map.take only picks keys a struct
  # has, so field and collection nodes compare on their own fact sets).
  # Origins are the one sanctioned difference between sources (D-004).
  @facts [
    :id,
    :name,
    :role,
    :value_type,
    :options,
    :default,
    :examples,
    :template_path,
    :required?,
    :read_only?,
    :constraints
  ]

  for fixture <- [Measurements, Addresses] do
    @fixture fixture

    describe "#{fixture |> Module.split() |> List.last()}" do
      setup do
        {:ok, from_map, []} =
          Formentation.compile(@fixture.map_source(), adapter: Formentation.Source.Map)

        {:ok, from_json, []} =
          Formentation.compile(@fixture.json_schema(),
            adapter: Formentation.Source.JSONSchema,
            ui: @fixture.ui_hints()
          )

        %{from_map: from_map, from_json: from_json}
      end

      test "both sources compile without diagnostics", ctx do
        assert Info.diagnostics(ctx.from_map) == []
        assert Info.diagnostics(ctx.from_json) == []
      end

      test "every semantic node fact matches apart from origins", ctx do
        assert_equivalent(Info.root(ctx.from_map), Info.root(ctx.from_json))
      end

      test "the validation asymmetry is preserved (D-054)", ctx do
        # Deliberately NOT validation equivalence: only the JSON Schema
        # source contributes an authoritative ValidationPlan; Map
        # cardinality is compiled facts only.
        assert ctx.from_map.validation == nil
        assert ctx.from_json.validation != nil
      end
    end
  end

  test "both spellings answer the same Info questions about the scalar collection" do
    {:ok, from_map, []} =
      Formentation.compile(Measurements.map_source(), adapter: Formentation.Source.Map)

    {:ok, from_json, []} =
      Formentation.compile(Measurements.json_schema(), adapter: Formentation.Source.JSONSchema)

    for definition <- [from_map, from_json] do
      assert Info.semantic_kind(definition, ["measurements"]) == :collection
      assert Info.required?(definition, ["measurements"])
      assert Info.constraints(definition, ["measurements"]) == %{min_items: 1, max_items: 10}

      assert %Semantic.Field{name: nil, value_type: :number} =
               Info.item_template(definition, ["measurements"])

      assert Info.semantic_kind(definition, ["measurements", 0]) == :field

      assert {:ok, %Formentation.Info.Layout.Collection{label: "Measurements"}} =
               Info.presentation_at(definition, ["measurements"])
    end
  end

  test "both spellings answer the same Info questions about the object collection" do
    {:ok, from_map, []} =
      Formentation.compile(Addresses.map_source(), adapter: Formentation.Source.Map)

    {:ok, from_json, []} =
      Formentation.compile(Addresses.json_schema(), adapter: Formentation.Source.JSONSchema)

    for definition <- [from_map, from_json] do
      assert Info.semantic_kind(definition, ["addresses"]) == :collection
      assert Info.semantic_kind(definition, ["addresses", 0]) == :object
      assert Info.required?(definition, ["addresses", 0, "street"])
      refute Info.required?(definition, ["addresses", 0, "zip"])
      assert Enum.map(Info.fields(definition), & &1.name) == ["street", "zip"]

      assert {:ok, %Formentation.Info.Layout.Object{label: "Address"}} =
               Info.presentation_at(definition, ["addresses", 5])
    end
  end

  test "each side carries its own source's origin tags at the collection path" do
    {:ok, from_map, []} =
      Formentation.compile(Measurements.map_source(), adapter: Formentation.Source.Map)

    {:ok, from_json, []} =
      Formentation.compile(Measurements.json_schema(), adapter: Formentation.Source.JSONSchema)

    map_tags = for {_key, {tag, _ref}} <- Info.origins(from_map, ["measurements"]), do: tag
    json_tags = for {_key, {tag, _ref}} <- Info.origins(from_json, ["measurements"]), do: tag

    assert map_tags != []
    assert json_tags != []
    assert Enum.all?(map_tags, &(&1 in [:map_source, :inference]))
    assert Enum.all?(json_tags, &(&1 in [:json_schema, :ui_hints, :inference]))
  end

  defp assert_equivalent(left, right) do
    assert left.__struct__ == right.__struct__,
           "nodes #{inspect(left.id)} and #{inspect(right.id)} differ in kind"

    assert Map.take(left, @facts) == Map.take(right, @facts),
           "nodes #{inspect(left.id)} and #{inspect(right.id)} differ"

    left_children = children_by_id(left)
    right_children = children_by_id(right)

    assert map_size(left_children) == map_size(right_children),
           "children of #{inspect(left.id)} differ in count"

    for {id, child} <- left_children do
      assert Map.has_key?(right_children, id), "right side is missing child #{inspect(id)}"
      assert_equivalent(child, Map.fetch!(right_children, id))
    end
  end

  defp children_by_id(node), do: Map.new(children_of(node), &{&1.id, &1})

  defp children_of(%Semantic.Object{children: children}), do: children
  defp children_of(%Semantic.Collection{item: item}), do: [item]
  defp children_of(_leaf), do: []
end
