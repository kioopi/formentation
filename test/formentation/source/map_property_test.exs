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

  defp scalar_term do
    StreamData.one_of([
      StreamData.string(:printable, max_length: 10),
      StreamData.integer(),
      StreamData.float(),
      StreamData.boolean(),
      StreamData.atom(:alphanumeric),
      StreamData.constant(nil)
    ])
  end

  defp arbitrary_term(0), do: scalar_term()

  defp arbitrary_term(depth) do
    StreamData.frequency([
      {3, scalar_term()},
      {2, StreamData.list_of(arbitrary_term(depth - 1), max_length: 4)},
      {2,
       StreamData.map_of(
         StreamData.string(:alphanumeric, max_length: 6),
         arbitrary_term(depth - 1),
         max_length: 4
       )},
      {1, StreamData.tuple({arbitrary_term(depth - 1), arbitrary_term(depth - 1)})}
    ])
  end

  property "compiling arbitrary terms never raises" do
    check all(term <- arbitrary_term(3)) do
      assert_total_result(
        Formentation.compile(term, adapter: Formentation.Source.Map, max_depth: 8, max_nodes: 100)
      )
    end
  end

  defp scalar_kind, do: StreamData.member_of([:string, :integer, :number, :boolean])

  defp field_spec do
    StreamData.bind(scalar_kind(), fn kind -> StreamData.constant(%{kind: kind}) end)
  end

  defp corrupted_property_entry do
    StreamData.frequency([
      {5,
       StreamData.bind(StreamData.string(:alphanumeric, min_length: 1, max_length: 8), fn name ->
         StreamData.bind(field_spec(), fn spec -> StreamData.constant({name, spec}) end)
       end)},
      {1, StreamData.constant(nil)},
      {1, StreamData.string(:alphanumeric, max_length: 5)},
      {1,
       StreamData.bind(StreamData.atom(:alphanumeric), fn name ->
         StreamData.bind(field_spec(), fn spec -> StreamData.constant({name, spec}) end)
       end)},
      {1,
       StreamData.bind(StreamData.string(:alphanumeric, min_length: 1, max_length: 8), fn name ->
         StreamData.map(StreamData.integer(), fn value -> {name, value} end)
       end)}
    ])
  end

  defp almost_valid_object do
    StreamData.bind(
      StreamData.list_of(corrupted_property_entry(), max_length: 5),
      fn properties ->
        StreamData.constant(%{kind: :object, properties: properties})
      end
    )
  end

  property "compiling almost-valid declarations with occasionally malformed entries never raises" do
    check all(declaration <- almost_valid_object()) do
      assert_total_result(
        Formentation.compile(declaration,
          adapter: Formentation.Source.Map,
          max_depth: 8,
          max_nodes: 100
        )
      )
    end
  end

  defp assert_total_result({:ok, %Formentation.Definition{}, diagnostics})
       when is_list(diagnostics),
       do: :ok

  defp assert_total_result({:error, [%Formentation.Diagnostic{} | _]}), do: :ok

  defp assert_total_result(other) do
    flunk("expected a total compilation result, got: #{inspect(other)}")
  end
end
