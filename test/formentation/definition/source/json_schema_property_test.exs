defmodule Formentation.Definition.Source.JSONSchemaPropertyTest do
  # async: false — the atom-count assertion measures the global VM atom
  # table, which would otherwise race against atoms allocated by
  # concurrently running async test suites.
  use ExUnit.Case, async: false
  use ExUnitProperties

  property "compilation terminates within the depth budget for nested schemas" do
    check all(depth <- StreamData.integer(1..30)) do
      result =
        Formentation.compile(nested(depth),
          adapter: Formentation.Definition.Source.JSONSchema,
          max_depth: 16
        )

      case result do
        {:ok, _definition, _diagnostics} ->
          assert depth <= 16

        {:error, [diagnostic]} ->
          assert diagnostic.code == :max_depth_exceeded
          assert depth > 16
      end
    end
  end

  property "compilation terminates within the node budget for wide schemas" do
    check all(width <- StreamData.integer(1..50)) do
      properties = for i <- 1..width, into: %{}, do: {"field_#{i}", %{"type" => "string"}}

      result =
        Formentation.compile(%{"type" => "object", "properties" => properties},
          adapter: Formentation.Definition.Source.JSONSchema,
          max_nodes: 20
        )

      case result do
        {:ok, definition, _diagnostics} ->
          assert width <= 19
          assert Enum.count(Formentation.Info.fields(definition)) == width

        {:error, [diagnostic]} ->
          assert diagnostic.code == :max_nodes_exceeded
          assert width > 19
      end
    end
  end

  defp nested(0), do: %{"type" => "object", "properties" => %{"leaf" => %{"type" => "string"}}}

  defp nested(depth) do
    %{"type" => "object", "properties" => %{"level" => nested(depth - 1)}}
  end

  test "compiling schemas and hints with arbitrary names creates no atoms" do
    # Warm-up so module/anonymous-function atoms are already allocated,
    # covering every hint path (known widget, unknown widget, unknown field).
    {:ok, _, _} =
      Formentation.compile(
        %{"type" => "object", "properties" => %{"warmup" => %{"type" => "string"}}},
        adapter: Formentation.Definition.Source.JSONSchema,
        ui: %{
          "order" => ["warmup", "bogus"],
          "groups" => [%{"id" => "g", "title" => "G", "fields" => ["warmup"]}],
          "fields" => %{
            "warmup" => %{"widget" => "textarea", "help" => "h"},
            "missing" => %{"widget" => "carousel"}
          }
        }
      )

    names = for i <- 1..50, do: "prop_#{System.unique_integer([:positive])}_#{i}"

    properties =
      Map.new(
        names,
        &{&1,
         %{
           "type" => "string",
           "format" => "mystery_#{&1}",
           "description" => "about #{&1}",
           "examples" => ["example #{&1}"],
           "default" => "default #{&1}",
           "const" => "value #{&1}"
         }}
      )

    ui = %{
      "order" => Enum.take(names, 10),
      "groups" => [%{"id" => "gen_group", "fields" => Enum.take(names, 3)}],
      "fields" => Map.new(Enum.take(names, 5), &{&1, %{"widget" => "widget_#{&1}"}})
    }

    atoms_before = :erlang.system_info(:atom_count)

    {:ok, definition, _diagnostics} =
      Formentation.compile(%{"type" => "object", "properties" => properties},
        adapter: Formentation.Definition.Source.JSONSchema,
        ui: ui
      )

    assert :erlang.system_info(:atom_count) == atoms_before
    assert Enum.count(Formentation.Info.fields(definition)) == 50
  end

  property "field order is deterministic regardless of map construction order" do
    name = StreamData.string(:alphanumeric, min_length: 1, max_length: 12)

    check all(names <- StreamData.uniq_list_of(name, min_length: 1, max_length: 20)) do
      properties =
        names
        |> Enum.shuffle()
        |> Map.new(&{&1, %{"type" => "string"}})

      {:ok, definition, _diagnostics} =
        Formentation.compile(%{"type" => "object", "properties" => properties},
          adapter: Formentation.Definition.Source.JSONSchema
        )

      assert Enum.map(Formentation.Info.fields(definition), & &1.name) == Enum.sort(names)
    end
  end

  test "compiling each shared fixture twice is identical" do
    for fixture <- [Formentation.Fixtures.PumpInspection, Formentation.Fixtures.Annotations] do
      compile = fn ->
        {:ok, definition, []} =
          Formentation.compile(fixture.json_schema(),
            adapter: Formentation.Definition.Source.JSONSchema,
            ui: fixture.ui_hints()
          )

        definition
      end

      assert compile.() == compile.()
    end
  end
end
