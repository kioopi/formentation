defmodule Formentation.Info.LayoutTest do
  use ExUnit.Case, async: true

  alias Formentation.{Definition, Info, TemplatePath}
  alias Formentation.Definition.Presentation, as: LayoutStorage
  alias Formentation.Definition.Semantic
  alias Formentation.Info.Layout

  defp compile!(declaration) do
    {:ok, definition, _diagnostics} =
      Formentation.compile(declaration, adapter: Formentation.Source.Map)

    definition
  end

  defp paths(%Layout.Object{children: children}), do: Enum.flat_map(children, &paths/1)
  defp paths(%Layout.Group{children: children}), do: Enum.flat_map(children, &paths/1)
  defp paths(%Layout.Field{semantic_path: path}), do: [path.segments]

  defp malformed_definition(semantic, presentation, by_id \\ %{}) do
    %Definition{
      semantic: semantic,
      semantic_index: %Semantic.Index{by_id: by_id},
      presentation: presentation
    }
  end

  test "ungrouped root layout follows declaration order and is deterministic" do
    definition =
      compile!(%{
        kind: :object,
        properties: [{"a", %{kind: :string}}, {"c", %{kind: :string}}]
      })

    root = Info.presentation_root(definition)

    assert %Layout.Object{semantic_path: %{segments: []}} = root
    assert paths(root) == [["a"], ["c"]]
    assert Info.presentation_root(definition) == root
  end

  test "presentation order can differ from semantic declaration order" do
    definition =
      compile!(%{
        kind: :object,
        properties: [{"a", %{kind: :string}}, {"c", %{kind: :string}}],
        groups: [%{id: "reordered", fields: ["c", "a"]}]
      })

    assert definition |> Info.fields() |> Enum.map(& &1.name) == ["a", "c"]

    assert %Layout.Object{
             children: [%Layout.Group{id: "/#reordered"} = group]
           } = Info.presentation_root(definition)

    assert paths(group) == [["c"], ["a"]]
  end

  test "non-adjacent grouped members preserve group placement and explicit group order" do
    definition =
      compile!(%{
        kind: :object,
        properties: [
          {"a", %{kind: :string}},
          {"b", %{kind: :string}},
          {"c", %{kind: :string}},
          {"d", %{kind: :string}}
        ],
        groups: [%{id: "late", fields: ["d", "b"]}]
      })

    assert %Layout.Object{
             children: [
               %Layout.Field{semantic_path: %{segments: ["a"]}},
               %Layout.Group{id: "/#late"} = group,
               %Layout.Field{semantic_path: %{segments: ["c"]}}
             ]
           } = Info.presentation_root(definition)

    assert paths(group) == [["d"], ["b"]]
  end

  test "nested objects add path segments but inner presentation groups do not" do
    definition =
      compile!(%{
        kind: :object,
        properties: [
          {"details",
           %{
             kind: :object,
             properties: [{"width", %{kind: :integer}}, {"height", %{kind: :integer}}],
             groups: [%{id: "technical", fields: ["height", "width"]}]
           }}
        ]
      })

    assert %Layout.Object{
             children: [
               %Layout.Object{
                 semantic_path: %{segments: ["details"]},
                 children: [%Layout.Group{id: "/details#technical"} = group]
               }
             ]
           } = Info.presentation_root(definition)

    assert paths(group) == [["details", "height"], ["details", "width"]]
    assert Info.presentation_at(definition, ["details", "technical", "width"]) == :not_found
  end

  test "presentation descriptors own presentation metadata only" do
    definition =
      compile!(%{
        kind: :object,
        title: "Asset",
        help: "Top level help.",
        properties: [
          {"mode",
           %{
             kind: :string,
             title: "Mode",
             help: "Choose carefully.",
             one_of: ["auto", "manual"],
             widget: :radio,
             hidden: true,
             read_only: true
           }}
        ]
      })

    assert {:ok,
            %Layout.Field{
              semantic_path: %{segments: ["mode"]},
              label: "Mode",
              help: "Choose carefully.",
              widget: :radio,
              hidden?: true
            }} = Info.presentation_at(definition, ["mode"])

    assert %Semantic.Field{options: ["auto", "manual"], read_only?: true, value_type: :string} =
             Info.node_at(definition, ["mode"])
  end

  test "every emitted field and object reference resolves to the expected semantic kind" do
    definition =
      compile!(%{
        kind: :object,
        properties: [
          {"title", %{kind: :string}},
          {"details", %{kind: :object, properties: [{"width", %{kind: :integer}}]}},
          {"legacy", %{kind: :file}}
        ],
        groups: [%{id: "main", fields: ["legacy", "title"]}]
      })

    refs =
      definition
      |> Info.presentation_root()
      |> collect_refs()

    assert refs == [
             {:object, []},
             {:field, ["title"]},
             {:object, ["details"]},
             {:field, ["details", "width"]}
           ]

    for {:object, path} <- refs do
      assert match?(%Semantic.Object{}, Info.node_at(definition, path))
    end

    for {:field, path} <- refs do
      assert match?(%Semantic.Field{}, Info.node_at(definition, path))
    end
  end

  test "subtree lookup distinguishes root, fields, objects, missing paths, and unsupported paths" do
    definition =
      compile!(%{
        kind: :object,
        properties: [
          {"title", %{kind: :string}},
          {"details",
           %{
             kind: :object,
             properties: [{"width", %{kind: :integer}}, {"attachment", %{kind: :file}}],
             groups: [%{id: "technical", fields: ["width", "attachment"]}]
           }}
        ],
        groups: [%{id: "main", fields: ["title"]}]
      })

    assert {:ok, %Layout.Object{semantic_path: %{segments: []}}} =
             Info.presentation_at(definition, [])

    assert {:ok, %Layout.Field{semantic_path: %{segments: ["title"]}}} =
             Info.presentation_at(definition, ["title"])

    assert {:ok, %Layout.Object{semantic_path: %{segments: ["details"]}}} =
             Info.presentation_at(definition, ["details"])

    assert {:ok, %Layout.Field{semantic_path: %{segments: ["details", "width"]}}} =
             Info.presentation_at(definition, ["details", "width"])

    assert Info.presentation_at(definition, ["missing"]) == :not_found
    assert Info.presentation_at(definition, ["details", "attachment"]) == :unsupported
    assert Info.presentation_at(definition, ["main"]) == :not_found
    assert Info.presentation_at(definition, ["details", "technical"]) == :not_found
  end

  test "presentation_root/1 raises when the root semantic reference has the wrong kind" do
    semantic = Semantic.Object.new(nil, %TemplatePath{segments: []}, [])
    presentation = LayoutStorage.Object.new("/", [])

    definition =
      malformed_definition(semantic, presentation, %{
        "/" => %{kind: :field, node: semantic}
      })

    assert_raise ArgumentError,
                 ~r/invalid presentation reference \[\]: expected a object occurrence, found field/,
                 fn ->
                   Info.presentation_root(definition)
                 end
  end

  test "presentation_root/1 raises when the root semantic reference is missing" do
    semantic = Semantic.Object.new(nil, %TemplatePath{segments: []}, [])
    presentation = LayoutStorage.Object.new("/", [])
    definition = malformed_definition(semantic, presentation)

    assert_raise ArgumentError,
                 ~r/invalid presentation reference "\/": expected a object occurrence, found none/,
                 fn ->
                   Info.presentation_root(definition)
                 end
  end

  test "presentation_root/1 raises clearly when presentation storage is missing" do
    definition =
      malformed_definition(Semantic.Object.new(nil, %TemplatePath{segments: []}, []), nil)

    assert_raise ArgumentError,
                 "invalid presentation query: definition has no presentation storage",
                 fn ->
                   Info.presentation_root(definition)
                 end
  end

  test "presentation_at/2 raises when a semantic occurrence has no layout descriptor" do
    field = Semantic.Field.new("name", %TemplatePath{segments: ["name"]}, :string)
    semantic = Semantic.Object.new(nil, %TemplatePath{segments: []}, [field])
    presentation = LayoutStorage.Object.new("/", [])

    definition =
      malformed_definition(semantic, presentation, %{
        "/" => %{kind: :object, node: semantic},
        "/name" => %{kind: :field, node: field}
      })

    assert_raise ArgumentError,
                 ~r/invalid presentation reference "\/name": expected exactly one presentation descriptor, found none/,
                 fn ->
                   Info.presentation_at(definition, ["name"])
                 end
  end

  test "presentation_at/2 raises clearly when presentation storage is missing" do
    field = Semantic.Field.new("name", %TemplatePath{segments: ["name"]}, :string)

    definition =
      malformed_definition(
        Semantic.Object.new(nil, %TemplatePath{segments: []}, [field]),
        nil,
        %{"/name" => %{kind: :field, node: field}}
      )

    assert_raise ArgumentError,
                 "invalid presentation query: definition has no presentation storage",
                 fn ->
                   Info.presentation_at(definition, ["name"])
                 end
  end

  test "presentation_root/1 builds semantic paths from the semantic index entry" do
    semantic = Semantic.Object.new(nil, %TemplatePath{segments: []}, [])
    field = Semantic.Field.new("name", %TemplatePath{segments: ["name"]}, :string)

    definition =
      malformed_definition(
        semantic,
        LayoutStorage.Object.new("/", [LayoutStorage.Field.new("/name")]),
        %{
          "/" => %{kind: :object, node: semantic},
          "/name" => %{kind: :field, node: field}
        }
      )

    assert %Layout.Object{
             children: [%Layout.Field{semantic_path: %{segments: ["name"]}}]
           } = Info.presentation_root(definition)
  end

  test "presentation_at/2 raises on ambiguous hand-built semantic paths" do
    semantic =
      Semantic.Object.new(nil, %TemplatePath{segments: []}, [
        Semantic.Field.new("name", %TemplatePath{segments: ["name"]}, :string),
        Semantic.Field.new("name", %TemplatePath{segments: ["name"]}, :string, id: "/other-name")
      ])

    definition = malformed_definition(semantic, LayoutStorage.Object.new("/", []))

    assert_raise ArgumentError,
                 ~r/invalid presentation reference \["name"\]: expected exactly one semantic occurrence, found 2/,
                 fn ->
                   Info.presentation_at(definition, ["name"])
                 end
  end

  defp collect_refs(%Layout.Object{semantic_path: path, children: children}) do
    [{:object, path.segments} | Enum.flat_map(children, &collect_refs/1)]
  end

  defp collect_refs(%Layout.Group{children: children}) do
    Enum.flat_map(children, &collect_refs/1)
  end

  defp collect_refs(%Layout.Field{semantic_path: path}) do
    [{:field, path.segments}]
  end
end
