defmodule Formentation.DifferentialTest do
  use ExUnit.Case, async: true

  alias Formentation.Definition.Semantic
  alias Formentation.Fixtures.{Annotations, FieldAccess, PumpInspection}
  alias Formentation.Info
  alias Formentation.Info.Layout

  # Every node fact the differential test compares. Origins are excluded
  # deliberately: they are the one sanctioned difference between sources
  # (D-004); they get their own assertions below.
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

  for fixture <- [PumpInspection, Annotations, FieldAccess] do
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

      test "both sources compile the fixture without diagnostics", ctx do
        assert Info.diagnostics(ctx.from_map) == []
        assert Info.diagnostics(ctx.from_json) == []
      end

      test "fields use each source's semantic order", ctx do
        assert Enum.map(Info.fields(ctx.from_map), & &1.name) == @fixture.field_names()

        assert Enum.map(Info.fields(ctx.from_json), & &1.name) ==
                 Enum.sort(@fixture.field_names())
      end

      test "every node fact matches apart from origins", ctx do
        assert_equivalent(Info.root(ctx.from_map), Info.root(ctx.from_json))
      end

      test "every presentation fact matches apart from origins", ctx do
        assert presentation_facts(ctx.from_map) == presentation_facts(ctx.from_json)
      end

      test "each side carries its own source's origin tags", ctx do
        for name <- @fixture.field_names() do
          map_tags = for {_key, {tag, _ref}} <- Info.origins(ctx.from_map, [name]), do: tag
          json_tags = for {_key, {tag, _ref}} <- Info.origins(ctx.from_json, [name]), do: tag

          assert map_tags != [], "map-source node #{name} has no origins"
          assert json_tags != [], "json-schema node #{name} has no origins"
          assert Enum.all?(map_tags, &(&1 in [:map_source, :inference]))
          assert Enum.all?(json_tags, &(&1 in [:json_schema, :ui_hints, :inference]))
        end
      end
    end
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
  defp children_of(_leaf), do: []

  defp presentation_facts(definition) do
    definition
    |> Info.presentation_root()
    |> collect_presentation_facts()
    |> Enum.sort()
  end

  defp collect_presentation_facts(%Layout.Object{} = object) do
    [
      {:object, object.semantic_path.segments, object.label, object.help}
      | Enum.flat_map(object.children, &collect_presentation_facts/1)
    ]
  end

  defp collect_presentation_facts(%Layout.Group{} = group) do
    [
      {:group, group.id, group.label, group.help}
      | Enum.flat_map(group.children, &collect_presentation_facts/1)
    ]
  end

  defp collect_presentation_facts(%Layout.Field{} = field) do
    [
      {:field, field.semantic_path.segments, field.label, field.help, field.widget, field.hidden?}
    ]
  end
end
