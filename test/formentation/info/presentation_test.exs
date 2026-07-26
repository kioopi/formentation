defmodule Formentation.Info.PresentationTest do
  use ExUnit.Case, async: true

  alias Formentation.Info
  alias Formentation.Info.Presentation
  alias Formentation.Node

  defp compile!(declaration) do
    {:ok, definition, _diagnostics} =
      Formentation.compile(declaration, adapter: Formentation.Source.Map)

    definition
  end

  defp paths(%Presentation.Object{children: children}), do: Enum.flat_map(children, &paths/1)
  defp paths(%Presentation.Group{children: children}), do: Enum.flat_map(children, &paths/1)
  defp paths(%Presentation.Field{semantic_path: path}), do: [path.segments]

  test "ungrouped root layout follows declaration order and is deterministic" do
    definition =
      compile!(%{
        kind: :object,
        properties: [{"a", %{kind: :string}}, {"c", %{kind: :string}}]
      })

    root = Info.presentation_root(definition)

    assert %Presentation.Object{semantic_path: %{segments: []}} = root
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

    assert %Presentation.Object{
             children: [%Presentation.Group{id: "/#reordered"} = group]
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

    assert %Presentation.Object{
             children: [
               %Presentation.Field{semantic_path: %{segments: ["a"]}},
               %Presentation.Group{id: "/#late"} = group,
               %Presentation.Field{semantic_path: %{segments: ["c"]}}
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

    assert %Presentation.Object{
             children: [
               %Presentation.Object{
                 semantic_path: %{segments: ["details"]},
                 children: [%Presentation.Group{id: "/details#technical"} = group]
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
            %Presentation.Field{
              semantic_path: %{segments: ["mode"]},
              label: "Mode",
              help: "Choose carefully.",
              widget: :radio,
              hidden?: true
            }} = Info.presentation_at(definition, ["mode"])

    assert %Node.Field{options: ["auto", "manual"], read_only?: true, value_type: :string} =
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
      assert match?(%Node.Group{}, Info.node_at(definition, path))
    end

    for {:field, path} <- refs do
      assert match?(%Node.Field{}, Info.node_at(definition, path))
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

    assert {:ok, %Presentation.Object{semantic_path: %{segments: []}}} =
             Info.presentation_at(definition, [])

    assert {:ok, %Presentation.Field{semantic_path: %{segments: ["title"]}}} =
             Info.presentation_at(definition, ["title"])

    assert {:ok, %Presentation.Object{semantic_path: %{segments: ["details"]}}} =
             Info.presentation_at(definition, ["details"])

    assert {:ok, %Presentation.Field{semantic_path: %{segments: ["details", "width"]}}} =
             Info.presentation_at(definition, ["details", "width"])

    assert Info.presentation_at(definition, ["missing"]) == :not_found
    assert Info.presentation_at(definition, ["details", "attachment"]) == :unsupported
    assert Info.presentation_at(definition, ["main"]) == :not_found
    assert Info.presentation_at(definition, ["details", "technical"]) == :not_found
  end

  defp collect_refs(%Presentation.Object{semantic_path: path, children: children}) do
    [{:object, path.segments} | Enum.flat_map(children, &collect_refs/1)]
  end

  defp collect_refs(%Presentation.Group{children: children}) do
    Enum.flat_map(children, &collect_refs/1)
  end

  defp collect_refs(%Presentation.Field{semantic_path: path}) do
    [{:field, path.segments}]
  end
end
