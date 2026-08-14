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

  test "the totality generators do not grow the atom table" do
    warmup_totality_compile_paths()

    # One full priming pass first: the *first* time the VM formats/inspects a
    # never-before-seen term shape (e.g. a bare root map with no `:kind` key,
    # a raw tuple), Erlang/Elixir's own inspect/protocol machinery can pay a
    # one-time setup cost that shows up as new atoms — that's global runtime
    # state, not a per-declaration leak in these generators or in
    # Formentation.Source.Map. Confirmed by hand: repeating the exact same
    # compile call a second time costs zero new atoms. So prime once
    # (discarded), then assert the *next* equally-sized pass is flat.
    run_totality_generators()

    atoms_before = :erlang.system_info(:atom_count)

    run_totality_generators()

    assert :erlang.system_info(:atom_count) == atoms_before
  end

  defp run_totality_generators do
    arbitrary_term(3)
    |> Enum.take(300)
    |> Enum.each(fn term ->
      Formentation.compile(term, adapter: Formentation.Source.Map, max_depth: 8, max_nodes: 100)
    end)

    almost_valid_object()
    |> Enum.take(300)
    |> Enum.each(fn declaration ->
      Formentation.compile(declaration,
        adapter: Formentation.Source.Map,
        max_depth: 8,
        max_nodes: 100
      )
    end)
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

  # A fixed pool of atoms already interned by this application (module
  # attributes and pattern-matched literals in Formentation.Source.Map and
  # its Semantic/Presentation structs) — reusing them, instead of minting
  # fresh atoms via StreamData.atom/1, keeps a long `check all` run from
  # growing the VM atom table (see the atom-table-stability test above).
  @safe_atoms [
    :string,
    :integer,
    :number,
    :boolean,
    :object,
    :select,
    :text,
    :ok,
    :error
  ]

  # A fixed vocabulary of declaration keywords, reused as atom map keys so
  # arbitrary_term/1 can occasionally produce an atom-keyed, declaration-
  # shaped map (e.g. a random `:kind` key) without minting fresh atoms.
  @declaration_keys [
    :kind,
    :object,
    :string,
    :integer,
    :number,
    :boolean,
    :properties,
    :required,
    :groups,
    :id,
    :fields,
    :title,
    :help,
    :role,
    :widget,
    :default,
    :min,
    :max,
    :min_length,
    :max_length,
    :one_of,
    :examples,
    :collection,
    :item,
    :min_items,
    :max_items
  ]

  defp safe_atom, do: StreamData.member_of(@safe_atoms)

  defp arbitrary_key do
    StreamData.one_of([
      StreamData.string(:alphanumeric, max_length: 6),
      StreamData.member_of(@declaration_keys)
    ])
  end

  defp scalar_term do
    StreamData.one_of([
      StreamData.string(:printable, max_length: 10),
      StreamData.integer(),
      StreamData.float(),
      StreamData.boolean(),
      safe_atom(),
      StreamData.constant(nil)
    ])
  end

  defp arbitrary_term(0), do: scalar_term()

  defp arbitrary_term(depth) do
    StreamData.frequency([
      {3, scalar_term()},
      {2, StreamData.list_of(arbitrary_term(depth - 1), max_length: 4)},
      {2, StreamData.map_of(arbitrary_key(), arbitrary_term(depth - 1), max_length: 4)},
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

  defp property_name, do: StreamData.string(:alphanumeric, min_length: 1, max_length: 8)

  # 4-in-5 valid, 1-in-5 corrupted — biased toward valid so nested/recursive
  # structure actually forms often enough to exercise deep validation paths,
  # while still regularly injecting a malformed value at this boundary.
  defp maybe_corrupt(valid, corrupt) do
    StreamData.frequency([{4, valid}, {1, corrupt}])
  end

  defp almost_valid_atom_or_nil do
    maybe_corrupt(
      StreamData.one_of([StreamData.constant(nil), safe_atom()]),
      StreamData.one_of([StreamData.string(:alphanumeric, max_length: 5), StreamData.integer()])
    )
  end

  defp almost_valid_string_or_nil do
    maybe_corrupt(
      StreamData.one_of([
        StreamData.constant(nil),
        StreamData.string(:alphanumeric, max_length: 8)
      ]),
      StreamData.one_of([StreamData.integer(), safe_atom()])
    )
  end

  defp almost_valid_default(:string),
    do: maybe_corrupt(StreamData.string(:alphanumeric, max_length: 5), safe_atom())

  defp almost_valid_default(:integer),
    do: maybe_corrupt(StreamData.integer(), StreamData.string(:alphanumeric, max_length: 3))

  defp almost_valid_default(:number) do
    maybe_corrupt(
      StreamData.one_of([StreamData.integer(), StreamData.float()]),
      StreamData.string(:alphanumeric, max_length: 3)
    )
  end

  defp almost_valid_default(:boolean),
    do: maybe_corrupt(StreamData.boolean(), StreamData.string(:alphanumeric, max_length: 3))

  defp almost_valid_bound do
    maybe_corrupt(
      StreamData.integer(0..10),
      StreamData.one_of([
        StreamData.integer(-5..-1),
        StreamData.string(:alphanumeric, max_length: 3)
      ])
    )
  end

  defp almost_valid_constraints(:string) do
    StreamData.bind(almost_valid_bound(), fn min_length ->
      StreamData.bind(almost_valid_bound(), fn max_length ->
        StreamData.constant(%{min_length: min_length, max_length: max_length})
      end)
    end)
  end

  defp almost_valid_constraints(kind) when kind in [:integer, :number] do
    StreamData.bind(almost_valid_bound(), fn min ->
      StreamData.bind(almost_valid_bound(), fn max ->
        StreamData.constant(%{min: min, max: max})
      end)
    end)
  end

  defp almost_valid_constraints(:boolean), do: StreamData.constant(%{})

  defp almost_valid_field_spec do
    gen all(
          kind <- scalar_kind(),
          role <- almost_valid_atom_or_nil(),
          widget <- almost_valid_atom_or_nil(),
          title <- almost_valid_string_or_nil(),
          help <- almost_valid_string_or_nil(),
          default <- almost_valid_default(kind),
          constraints <- almost_valid_constraints(kind)
        ) do
      Map.merge(
        %{kind: kind, role: role, widget: widget, title: title, help: help, default: default},
        constraints
      )
    end
  end

  defp almost_valid_property_spec(0), do: almost_valid_field_spec()

  defp almost_valid_property_spec(depth) do
    StreamData.frequency([
      {3, almost_valid_field_spec()},
      {1, almost_valid_object_spec(depth - 1)},
      {1, almost_valid_collection_spec(depth - 1)}
    ])
  end

  # Collections join the totality battery: valid specs form often enough
  # to reach item recursion; corruption covers every degradation row —
  # missing/non-map items, unsupported and nested item kinds, malformed
  # bounds, and every item-level `required` spelling.
  defp almost_valid_item_spec(0), do: almost_valid_field_spec()

  defp almost_valid_item_spec(depth) do
    StreamData.frequency([
      {4, almost_valid_field_spec()},
      {2, almost_valid_object_spec(depth - 1)},
      {1, StreamData.constant(%{kind: :datetime})},
      {1, almost_valid_collection_spec(depth - 1)},
      {1, StreamData.constant(nil)},
      {1, StreamData.string(:alphanumeric, max_length: 5)}
    ])
  end

  defp almost_valid_item_required do
    StreamData.frequency([
      {6, StreamData.constant(:absent)},
      {1, StreamData.boolean()},
      {1, StreamData.constant("yes")},
      {1, StreamData.list_of(StreamData.string(:alphanumeric, max_length: 4), max_length: 2)}
    ])
  end

  defp almost_valid_collection_spec(depth) do
    gen all(
          item <- almost_valid_item_spec(depth),
          min_items <- StreamData.one_of([StreamData.constant(:absent), almost_valid_bound()]),
          max_items <- StreamData.one_of([StreamData.constant(:absent), almost_valid_bound()]),
          required <- almost_valid_item_required(),
          drop_item? <-
            StreamData.frequency([
              {6, StreamData.constant(false)},
              {1, StreamData.constant(true)}
            ])
        ) do
      item =
        case {item, required} do
          {item, _required} when not is_map(item) -> item
          {item, :absent} -> item
          {item, required} -> Map.put(item, :required, required)
        end

      %{kind: :collection}
      |> put_unless(:item, item, drop_item?)
      |> put_unless(:min_items, min_items, min_items == :absent)
      |> put_unless(:max_items, max_items, max_items == :absent)
    end
  end

  defp put_unless(spec, _key, _value, true), do: spec
  defp put_unless(spec, key, value, false), do: Map.put(spec, key, value)

  defp almost_valid_property_entry(depth) do
    StreamData.frequency([
      {5,
       StreamData.bind(property_name(), fn name ->
         StreamData.bind(almost_valid_property_spec(depth), fn spec ->
           StreamData.constant({name, spec})
         end)
       end)},
      {1, StreamData.constant(nil)},
      {1, StreamData.string(:alphanumeric, max_length: 5)},
      {1,
       StreamData.bind(safe_atom(), fn name ->
         StreamData.bind(almost_valid_field_spec(), fn spec ->
           StreamData.constant({name, spec})
         end)
       end)},
      {1,
       StreamData.bind(property_name(), fn name ->
         StreamData.map(StreamData.integer(), fn value -> {name, value} end)
       end)}
    ])
  end

  defp almost_valid_group(names) do
    field_pool = Enum.uniq(names ++ ["unknown_field"])

    gen all(
          id <-
            maybe_corrupt(
              StreamData.string(:alphanumeric, min_length: 1, max_length: 6),
              safe_atom()
            ),
          fields <-
            maybe_corrupt(
              StreamData.list_of(StreamData.member_of(field_pool), max_length: 3),
              StreamData.one_of([
                StreamData.constant("oops"),
                StreamData.list_of(safe_atom(), max_length: 2)
              ])
            ),
          title <- almost_valid_string_or_nil()
        ) do
      %{id: id, fields: fields, title: title}
    end
  end

  defp almost_valid_groups(names),
    do: StreamData.list_of(almost_valid_group(names), max_length: 2)

  defp almost_valid_required([]), do: StreamData.constant([])

  defp almost_valid_required(names) do
    maybe_corrupt(
      StreamData.list_of(StreamData.member_of(names), max_length: 3),
      StreamData.list_of(
        StreamData.one_of([safe_atom(), StreamData.constant("unknown_required_name")]),
        max_length: 2
      )
    )
  end

  defp property_names_of(properties) do
    properties
    |> Enum.filter(&match?({name, _spec} when is_binary(name), &1))
    |> Enum.map(&elem(&1, 0))
  end

  defp almost_valid_object_spec(depth) do
    gen all(
          properties <- StreamData.list_of(almost_valid_property_entry(depth), max_length: 4),
          names = property_names_of(properties),
          required <- almost_valid_required(names),
          groups <- almost_valid_groups(names)
        ) do
      %{kind: :object, properties: properties, required: required, groups: groups}
    end
  end

  # Bounded at depth 2 — deep enough to reach nested-object, group, and
  # required validation, shallow enough to stay well under the compiler's
  # own max_depth budget passed below.
  defp almost_valid_object, do: almost_valid_object_spec(2)

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

  # Exercises every validator branch and typed-node constructor the totality
  # generators can reach at least once before the atom-table snapshot below,
  # so a one-time lazy compile-path cost elsewhere in the stack (e.g. a
  # dependency's first-use setup) doesn't get mistaken for a per-declaration
  # atom leak in the generators themselves.
  defp warmup_totality_compile_paths do
    valid = %{
      kind: :object,
      required: ["name"],
      properties: [
        {"name", %{kind: :string, min_length: 1, max_length: 10, role: :text, widget: :input}},
        {"count", %{kind: :integer, min: 0, max: 10, default: 1}},
        {"weight", %{kind: :number, default: 1.5}},
        {"active", %{kind: :boolean, default: true}},
        {"nested", %{kind: :object, properties: [{"leaf", %{kind: :string}}]}},
        {"measurements",
         %{kind: :collection, item: %{kind: :number}, min_items: 1, max_items: 10}}
      ],
      groups: [%{id: "g", title: "Group", fields: ["name", "count"]}]
    }

    malformed = [
      %{kind: "string"},
      %{kind: :object, properties: [{"x", %{kind: :not_a_kind_atom_or_string}}]},
      %{kind: :object, properties: [{"x", %{}}]},
      %{kind: :object, properties: [nil]},
      %{kind: :object, properties: [{"x", "not-a-spec"}]},
      %{kind: :object, required: [:x], properties: [{"x", %{kind: :string}}]},
      %{kind: :object, properties: [{"x", %{kind: :string, title: 1}}]},
      %{kind: :object, properties: [{"x", %{kind: :string, role: "role"}}]},
      %{kind: :object, properties: [{"x", %{kind: :string, widget: "widget"}}]},
      %{kind: :object, properties: [{"x", %{kind: :integer, default: "oops"}}]},
      %{kind: :object, properties: [{"x", %{kind: :integer, min_length: 1}}]},
      %{kind: :object, properties: [{"x", %{kind: :string, min_length: -1}}]},
      %{
        kind: :object,
        properties: [{"voltage", %{kind: :number}}],
        groups: [%{id: 1, fields: ["voltage"]}]
      },
      %{
        kind: :object,
        properties: [{"voltage", %{kind: :number}}],
        groups: [%{id: "g", fields: ["voltage"], title: 1}]
      },
      %{
        kind: :object,
        properties: [{"voltage", %{kind: :number}}],
        groups: [%{id: "g", fields: "voltage"}]
      },
      %{
        kind: :object,
        properties: [{"a", %{kind: :string}}, {"b", %{kind: :string}}],
        groups: [%{id: "g", fields: ["a"]}, %{id: "g", fields: ["b"]}]
      },
      %{kind: :object, properties: [{"_persistent_id", %{kind: :string}}]},
      %{kind: :object, properties: [{"m", %{kind: :collection}}]},
      %{kind: :object, properties: [{"m", %{kind: :collection, item: "x"}}]},
      %{
        kind: :object,
        properties: [{"m", %{kind: :collection, item: %{kind: :number}, min_items: -1}}]
      },
      %{
        kind: :object,
        properties: [
          {"m", %{kind: :collection, item: %{kind: :number}, min_items: 3, max_items: 1}}
        ]
      },
      %{
        kind: :object,
        properties: [{"m", %{kind: :collection, item: %{kind: :string, required: "yes"}}}]
      },
      %{
        kind: :object,
        properties: [{"m", %{kind: :collection, item: %{kind: :string, required: true}}}]
      },
      %{
        kind: :object,
        properties: [
          {"m", %{kind: :collection, item: %{kind: :collection, item: %{kind: :number}}}}
        ]
      },
      %{kind: :object, properties: [{"m", %{kind: :collection, item: %{kind: :datetime}}}]}
    ]

    Formentation.compile(valid, adapter: Formentation.Source.Map)

    Enum.each(malformed, fn declaration ->
      Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end)
  end

  defp assert_total_result({:ok, %Formentation.Definition{}, diagnostics})
       when is_list(diagnostics),
       do: :ok

  defp assert_total_result({:error, [%Formentation.Diagnostic{} | _]}), do: :ok

  defp assert_total_result(other) do
    flunk("expected a total compilation result, got: #{inspect(other)}")
  end
end
