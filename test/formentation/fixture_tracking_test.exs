defmodule Formentation.FixtureTrackingTest do
  @moduledoc """
  Pins that fixture JSON is tracked as an external resource. Without it,
  editing a fixture marks nothing stale and `mix test --stale` — what
  `mix test.dev` runs — selects zero tests, reporting a green that
  proves nothing.
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
end
