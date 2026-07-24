defmodule Formentation.Source.MapPropertyTest do
  # async: false — the assertion measures the global VM atom table, which
  # would otherwise race against atoms allocated by concurrently running
  # async test suites.
  use ExUnit.Case, async: false
  use ExUnitProperties

  test "compiling declarations with arbitrary property names creates no atoms" do
    # Warm-up so module/anonymous-function atoms are already allocated.
    {:ok, _, _} =
      Formentation.compile(
        %{kind: :object, properties: [{"warmup", %{kind: :string}}]},
        adapter: Formentation.Source.Map
      )

    names = for i <- 1..50, do: "prop_#{System.unique_integer([:positive])}_#{i}"

    properties =
      Enum.map(
        names,
        &{&1,
         %{
           kind: :string,
           help: "help #{&1}",
           examples: ["example #{&1}"],
           default: "default #{&1}",
           one_of: ["first #{&1}", "second #{&1}"]
         }}
      )

    atoms_before = :erlang.system_info(:atom_count)

    {:ok, definition, []} =
      Formentation.compile(%{kind: :object, properties: properties},
        adapter: Formentation.Source.Map
      )

    assert :erlang.system_info(:atom_count) == atoms_before
    assert Enum.count(Formentation.Info.fields(definition)) == 50
  end

  property "compilation terminates within the depth budget for nested declarations" do
    check all(depth <- StreamData.integer(1..30)) do
      result =
        Formentation.compile(nested(depth),
          adapter: Formentation.Source.Map,
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

  property "compilation terminates within the node budget for wide declarations" do
    check all(width <- StreamData.integer(1..50)) do
      properties = for i <- 1..width, do: {"field_#{i}", %{kind: :string}}

      result =
        Formentation.compile(%{kind: :object, properties: properties},
          adapter: Formentation.Source.Map,
          max_nodes: 20
        )

      case result do
        {:ok, definition, _diagnostics} ->
          assert width <= 19
          assert length(Formentation.Info.fields(definition)) == width

        {:error, [diagnostic]} ->
          assert diagnostic.code == :max_nodes_exceeded
          assert width > 19
      end
    end
  end

  defp nested(0), do: %{kind: :object, properties: [{"leaf", %{kind: :string}}]}

  defp nested(depth) do
    %{kind: :object, properties: [{"level", nested(depth - 1)}]}
  end
end
