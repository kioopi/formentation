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
