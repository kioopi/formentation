defmodule Formentation.OccurrenceTest do
  use ExUnit.Case, async: true

  alias Formentation.Occurrence

  doctest Formentation.Occurrence

  defp compile!(declaration) do
    {:ok, definition, _diagnostics} =
      Formentation.compile(declaration, adapter: Formentation.Source.Map)

    definition
  end

  test "binds every semantic node 1:1 in Milestone A, root included" do
    definition =
      compile!(%{
        kind: :object,
        properties: [
          {"name", %{kind: :string}},
          {"address", %{kind: :object, properties: [{"street", %{kind: :string}}]}},
          {"attachment", %{kind: :file}}
        ]
      })

    occurrences = Occurrence.occurrences(definition, %{})

    assert Enum.map(occurrences, fn {entry, path} -> {entry.kind, path.segments} end) == [
             {:object, []},
             {:field, ["name"]},
             {:object, ["address"]},
             {:field, ["address", "street"]},
             {:unsupported, ["attachment"]}
           ]
  end

  test "each binding's instance path is an occurrence of the entry's template path" do
    definition =
      compile!(%{
        kind: :object,
        properties: [
          {"address", %{kind: :object, properties: [{"street", %{kind: :string}}]}}
        ]
      })

    for {entry, path} <- Occurrence.occurrences(definition, %{}) do
      assert Formentation.TemplatePath.matches?(entry.template_path, path)
    end
  end

  test "data does not change the Milestone A binding" do
    definition = compile!(%{kind: :object, properties: [{"name", %{kind: :string}}]})

    assert Occurrence.occurrences(definition, %{}) ==
             Occurrence.occurrences(definition, %{"name" => "x", "junk" => [1, 2]})
  end
end
