defmodule Formentation.FacadeTest do
  use ExUnit.Case, async: true

  defmodule SpyAdapter do
    @moduledoc false
    @behaviour Formentation.Source

    @impl true
    def compile(source, opts) do
      if pid = opts[:notify], do: send(pid, {:spy_adapter_opts, opts})

      case Keyword.fetch(opts, :result) do
        {:ok, result} -> result
        :error -> Formentation.Source.Map.compile(source, Keyword.delete(opts, :notify))
      end
    end
  end

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

    test "raises ArgumentError for an unsupported bare atom selector" do
      error =
        assert_raise ArgumentError, fn ->
          Formentation.compile(%{kind: :object, properties: []}, adapter: :xml)
        end

      assert error.message =~ ":xml"
      assert error.message =~ ":map"
      assert error.message =~ ":json_schema"
    end

    test "raises ArgumentError for a non-atom adapter term" do
      error =
        assert_raise ArgumentError, fn ->
          Formentation.compile(%{kind: :object, properties: []}, adapter: "map")
        end

      assert error.message =~ inspect("map")
      assert error.message =~ "adapter"
    end

    test "raises ArgumentError for a module that does not export compile/2" do
      error =
        assert_raise ArgumentError, fn ->
          Formentation.compile(%{kind: :object, properties: []}, adapter: Enum)
        end

      assert error.message =~ inspect(Enum)
      assert error.message =~ "compile/2"
    end
  end

  describe "compile/2 custom module adapters" do
    test "accepts a custom module exporting compile/2" do
      declaration = %{kind: :object, properties: [{"name", %{kind: :string}}]}

      assert Formentation.compile(declaration, adapter: SpyAdapter) ==
               Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test "forwards only the non-:adapter options to compile/2" do
      declaration = %{kind: :object, properties: []}

      Formentation.compile(declaration, adapter: SpyAdapter, notify: self())

      assert_received {:spy_adapter_opts, opts}
      assert opts == [notify: self()]
    end
  end
end
