defmodule Formentation.FacadeTest do
  use ExUnit.Case, async: true

  describe "compile/2 symbolic selectors" do
    test ":map selector produces the same result as the Formentation.Source.Map module" do
      declaration = %{
        kind: :object,
        properties: [{"name", %{kind: :string}}]
      }

      assert Formentation.compile(declaration, adapter: :map) ==
               Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test ":json_schema selector produces the same result as the Formentation.JSONSchema module, including ui hints" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "voltage" => %{"type" => "number"},
          "insulation_ok" => %{"type" => "boolean"}
        }
      }

      ui = %{
        "groups" => [
          %{
            "id" => "electrical",
            "title" => "Electrical",
            "fields" => ["voltage", "insulation_ok"]
          }
        ]
      }

      assert Formentation.compile(schema, adapter: :json_schema, ui: ui) ==
               Formentation.compile(schema, adapter: Formentation.JSONSchema, ui: ui)
    end
  end

  describe "compile/2 adapter resolution errors" do
    test "raises ArgumentError when :adapter is missing" do
      error =
        assert_raise ArgumentError, fn ->
          Formentation.compile(%{kind: :object, properties: []}, [])
        end

      assert error.message =~ ":adapter"
      assert error.message =~ ":map"
      assert error.message =~ ":json_schema"
    end
  end
end
