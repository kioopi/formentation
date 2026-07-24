defmodule Formentation.DifferentialTest do
  use ExUnit.Case, async: true

  alias Formentation.Fixtures.{Annotations, FieldAccess, PumpInspection}
  alias Formentation.{Info, Node}

  # Every node fact the differential test compares. Origins are excluded
  # deliberately: they are the one sanctioned difference between sources
  # (D-004); they get their own assertions below.
  @facts [
    :id,
    :name,
    :label,
    :help,
    :role,
    :value_type,
    :widget,
    :group,
    :options,
    :default,
    :examples,
    :template_path,
    :required?,
    :hidden?,
    :read_only?,
    :nests_data?,
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
            adapter: Formentation.JSONSchema,
            ui: @fixture.ui_hints()
          )

        %{from_map: from_map, from_json: from_json}
      end

      test "both sources compile the fixture without diagnostics", ctx do
        assert Info.diagnostics(ctx.from_map) == []
        assert Info.diagnostics(ctx.from_json) == []
      end

      test "fields agree in name and order with the canonical fixture order", ctx do
        assert Enum.map(Info.fields(ctx.from_map), & &1.name) == @fixture.field_names()
        assert Enum.map(Info.fields(ctx.from_json), & &1.name) == @fixture.field_names()
      end

      test "every node fact matches apart from origins", ctx do
        assert_equivalent(Info.root(ctx.from_map), Info.root(ctx.from_json))
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

    assert Enum.count(children_of(left)) == Enum.count(children_of(right)),
           "children of #{inspect(left.id)} differ in count"

    children_of(left)
    |> Enum.zip(children_of(right))
    |> Enum.each(fn {l, r} -> assert_equivalent(l, r) end)
  end

  defp children_of(%Node.Group{children: children}), do: children
  defp children_of(_leaf), do: []
end
