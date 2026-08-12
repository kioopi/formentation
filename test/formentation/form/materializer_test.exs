defmodule Formentation.Form.MaterializerTest do
  use ExUnit.Case, async: true

  alias Formentation.Form.Materializer
  alias Formentation.{InstancePath, Issue}

  doctest Formentation.Form.Materializer

  defp definition do
    {:ok, definition, []} =
      Formentation.compile(
        %{
          kind: :object,
          properties: [{"age", %{kind: :integer}}, {"name", %{kind: :string}}]
        },
        adapter: Formentation.Source.Map
      )

    definition
  end

  test "set writes, unset omits, keep preserves the original value" do
    operations = %{
      InstancePath.new!(["age"]) => {:set, 42},
      InstancePath.new!(["name"]) => :unset
    }

    assert Materializer.materialize(definition(), %{"name" => "old"}, operations) ==
             {:ok, %{"age" => 42}}

    assert Materializer.materialize(definition(), %{"name" => "old"}, %{}) ==
             {:ok, %{"name" => "old"}}
  end

  test "keys the definition does not describe are preserved from the original" do
    assert Materializer.materialize(definition(), %{"unknown" => %{"deep" => 1}}, %{}) ==
             {:ok, %{"unknown" => %{"deep" => 1}}}
  end

  test "any invalid operation defers the whole candidate to :none" do
    issue = %Issue{
      path: InstancePath.new!(["age"]),
      code: :invalid_integer,
      message: "not an integer",
      source: :decode
    }

    operations = %{
      InstancePath.new!(["age"]) => {:invalid, issue},
      InstancePath.new!(["name"]) => {:set, "kept anyway? no"}
    }

    assert Materializer.materialize(definition(), %{}, operations) == :none
  end
end
