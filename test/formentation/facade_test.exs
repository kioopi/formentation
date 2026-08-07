defmodule Formentation.FacadeTest do
  use ExUnit.Case, async: true

  alias Formentation.Form

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

  describe "form/2 success path" do
    defp form_declaration do
      %{
        kind: :object,
        properties: [{"priority", %{kind: :string, default: "normal"}}]
      }
    end

    test "delegates to compile/2 then Form.new/3, matching a manual call" do
      {:ok, definition, diagnostics} = Formentation.compile(form_declaration(), adapter: :map)
      expected_form = Form.new(definition, %{"priority" => "high"}, defaults: :apply)

      assert Formentation.form(form_declaration(),
               adapter: :map,
               data: %{"priority" => "high"},
               defaults: :apply
             ) == {:ok, expected_form, diagnostics}
    end

    test "defaults :data to %{} when omitted" do
      {:ok, definition, diagnostics} = Formentation.compile(form_declaration(), adapter: :map)
      expected_form = Form.new(definition)

      assert Formentation.form(form_declaration(), adapter: :map) ==
               {:ok, expected_form, diagnostics}
    end
  end

  describe "form/2 failure path" do
    test "returns the compiler error and never calls Form.new/3" do
      diagnostics = [%Formentation.Diagnostic{code: :boom, severity: :error, message: "boom"}]

      assert Formentation.form(form_declaration(),
               adapter: SpyAdapter,
               result: {:error, diagnostics},
               data: "not a map"
             ) == {:error, diagnostics}
    end

    test "does not rescue a Form.new/3 failure after successful compilation" do
      assert_raise FunctionClauseError, fn ->
        Formentation.form(form_declaration(), adapter: :map, data: "not a map")
      end
    end
  end

  describe "form/2 option partitioning" do
    test "strips data: and defaults: while forwarding other options in order" do
      Formentation.form(form_declaration(),
        adapter: SpyAdapter,
        max_depth: 5,
        data: %{"priority" => "high"},
        notify: self(),
        defaults: :apply,
        max_nodes: 100
      )

      assert_received {:spy_adapter_opts, opts}
      assert opts == [max_depth: 5, notify: self(), max_nodes: 100]
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

  describe "compile/2 adapter resolution during compilation" do
    @describetag :tmp_dir

    test "accepts an adapter module still being compiled in the same run", %{tmp_dir: tmp_dir} do
      adapter_file = Path.join(tmp_dir, "late_adapter.ex")
      caller_file = Path.join(tmp_dir, "late_caller.ex")

      # The sleep forces the unfavourable ordering deterministically: the caller
      # resolves the adapter before the parallel compiler has produced it.
      File.write!(adapter_file, """
      Process.sleep(200)

      defmodule LateAdapter do
        def compile(_source, _opts), do: {:ok, :late_adapter_ran, []}
      end
      """)

      File.write!(caller_file, """
      defmodule LateCaller do
        @compiled Formentation.compile(%{kind: :object, properties: []}, adapter: LateAdapter)
        def compiled, do: @compiled
      end
      """)

      on_exit(fn ->
        for module <- [LateCaller, LateAdapter] do
          :code.purge(module)
          :code.delete(module)
        end
      end)

      assert {:ok, modules, _diagnostics} =
               Kernel.ParallelCompiler.compile([caller_file, adapter_file],
                 return_diagnostics: true
               )

      # Resolved through a runtime value: the module does not exist when this
      # test file itself is compiled.
      assert caller = Enum.find(modules, &(&1 == LateCaller))
      assert caller.compiled() == {:ok, :late_adapter_ran, []}
    end
  end
end
