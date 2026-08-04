defmodule Formentation.FixtureTrackingTest do
  @moduledoc """
  Pins that fixture JSON is tracked as an external resource, and that it is
  read at compile time rather than at runtime. Both halves are load-bearing
  and neither alone is enough: without `@external_resource`, editing a
  fixture marks nothing stale; with `@external_resource` but a runtime
  `File.read!` in a function body, the module still recompiles, but its
  `.beam` is byte-identical, so Elixir never marks dependents stale either.
  Either gap makes `mix test --stale` — what `mix test.dev` runs — select
  zero tests, reporting a green that proves nothing.
  """
  use ExUnit.Case, async: true

  defp external_resources(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:external_resource)
    |> List.flatten()
    |> Enum.map(&to_string/1)
  end

  defp tracks?(module, suffix) do
    module |> external_resources() |> Enum.any?(&String.ends_with?(&1, suffix))
  end

  test "the annotations fixture tracks both of its JSON documents" do
    assert tracks?(Formentation.Fixtures.Annotations, "annotations/schema.json")
    assert tracks?(Formentation.Fixtures.Annotations, "annotations/ui.json")
  end

  test "the field-access fixture tracks both of its JSON documents" do
    assert tracks?(Formentation.Fixtures.FieldAccess, "field_access/schema.json")
    assert tracks?(Formentation.Fixtures.FieldAccess, "field_access/ui.json")
  end

  test "the demo's pump-inspection declaration tracks both of its JSON documents" do
    assert tracks?(FormentationDemo.PumpInspection, "pump_inspection/schema.json")
    assert tracks?(FormentationDemo.PumpInspection, "pump_inspection/ui.json")
  end

  test "the embedded declarations still decode to the documents on disk" do
    on_disk =
      "test/support/fixtures/annotations/schema.json"
      |> File.read!()
      |> JSON.decode!()

    assert Formentation.Fixtures.Annotations.json_schema() == on_disk
  end

  describe "the fixture-owning modules read JSON at compile time, never at runtime" do
    # The four tests above cannot tell a working compile-time embed apart
    # from a silently-reverted runtime read: both `def json_schema, do:
    # @json_schema` and `def json_schema, do: File.read!(...) |> JSON.decode!()`
    # pass them equally, since neither test edits the JSON's *content* to
    # force a real staleness check. This source-text assertion pins the
    # mechanism directly instead: `File.read!` may appear only on the line
    # that assigns the `@json_schema`/`@ui_hints` module attribute — the one
    # place it runs once, at compile time — never inside a `def` body. A
    # failure here means a fixture module moved its JSON read back to
    # runtime, which silently restores the "No stale tests" bug
    # `mix test.dev` (and this whole file) exists to catch: the module still
    # recompiles on a JSON edit (`@external_resource` still forces that), but
    # the recompiled `.beam` is byte-identical, so `mix test --stale` selects
    # nothing.
    @annotations_source File.read!("test/support/fixtures/annotations.ex")
    @external_resource "test/support/fixtures/annotations.ex"

    @field_access_source File.read!("test/support/fixtures/field_access.ex")
    @external_resource "test/support/fixtures/field_access.ex"

    @pump_inspection_source File.read!("demo/formentation_demo/pump_inspection.ex")
    @external_resource "demo/formentation_demo/pump_inspection.ex"

    defp file_read_outside_attribute_assignment?(source) do
      source
      |> String.split("\n")
      |> Enum.any?(fn line ->
        String.contains?(line, "File.read!") and
          not Regex.match?(~r/^\s*@(json_schema|ui_hints)\b/, line)
      end)
    end

    test "the annotations fixture has no runtime File.read!" do
      refute file_read_outside_attribute_assignment?(@annotations_source)
    end

    test "the field-access fixture has no runtime File.read!" do
      refute file_read_outside_attribute_assignment?(@field_access_source)
    end

    test "the demo's pump-inspection declaration has no runtime File.read!" do
      refute file_read_outside_attribute_assignment?(@pump_inspection_source)
    end
  end
end
