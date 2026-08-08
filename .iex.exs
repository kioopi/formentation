# Loaded automatically by `iex -S mix`. Dev-console helpers for trying the
# library out; nothing here is compiled into the application.

defmodule Formentation.IExHelpers do
  @moduledoc false

  @fixture_dir "test/support/fixtures/pump_inspection"

  @doc """
  A small object declaration for the map source. Extra `{name, spec}`
  property tuples are appended to the defaults:

      fixture([{"age", %{kind: :integer, min: 0}}])
  """
  def fixture(extra_properties \\ []) do
    %{
      kind: :object,
      title: "Profile",
      required: ["name"],
      properties:
        [
          {"name", %{kind: :string, title: "Name", min_length: 2}},
          {"email", %{kind: :string, title: "Email"}},
          {"newsletter", %{kind: :boolean, title: "Newsletter"}}
        ] ++ extra_properties
    }
  end

  @doc """
  The same profile form as a decoded JSON Schema document (draft 2020-12,
  string keys — what `JSON.decode!/1` returns). Extra properties are
  merged in:

      schema(%{"age" => %{"type" => "integer", "minimum" => 0}})
  """
  def schema(extra_properties \\ %{}) do
    %{
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "type" => "object",
      "title" => "Profile",
      "required" => ["name"],
      "properties" =>
        Map.merge(
          %{
            "name" => %{"type" => "string", "title" => "Name", "minLength" => 2},
            "email" => %{"type" => "string", "title" => "Email", "format" => "email"},
            "newsletter" => %{"type" => "boolean", "title" => "Newsletter"}
          },
          extra_properties
        )
    }
  end

  @doc """
  A UI-hints document for `schema/0` showing the slice-2 vocabulary:
  explicit order, a presentation group, and a widget/help override.
  Pass it as the `ui:` option: `compile!(schema(), ui: ui_hints())`.
  """
  def ui_hints do
    %{
      "order" => ["name", "contact", "newsletter"],
      "groups" => [%{"id" => "contact", "title" => "Contact", "fields" => ["email"]}],
      "fields" => %{"email" => %{"widget" => "text", "help" => "We never share this."}}
    }
  end

  @doc """
  The end-to-end example (docs/Formentation/17-end-to-end-example.md) as
  `{schema, ui_hints}`, decoded from the checked-in fixture files.
  """
  def pump_inspection do
    read = fn name -> @fixture_dir |> Path.join(name) |> File.read!() |> JSON.decode!() end
    {read.("schema.json"), read.("ui.json")}
  end

  @doc """
  Compiles a declaration, prints any diagnostics, and returns the
  `Formentation.Definition`. Raises on error. The adapter is picked from
  the declaration's shape — `:kind` means the map source, anything else
  the JSON Schema source — and can be overridden with `adapter:`.
  """
  def compile!(declaration \\ fixture(), opts \\ []) do
    opts = Keyword.put_new(opts, :adapter, detect_adapter(declaration))

    case Formentation.compile(declaration, opts) do
      {:ok, definition, diagnostics} ->
        Enum.each(diagnostics, &IO.puts("#{&1.severity}: #{&1.message}"))
        definition

      {:error, diagnostics} ->
        raise "compile failed: " <> Enum.map_join(diagnostics, "; ", & &1.message)
    end
  end

  defp detect_adapter(%{kind: _kind}), do: Formentation.Source.Map
  defp detect_adapter(_declaration), do: Formentation.Source.JSONSchema
end

import Formentation.IExHelpers

alias Formentation.{Definition, Diagnostic, Info}
alias Formentation.Source
alias Formentation.Source.JSONSchema

IO.puts("""

Formentation dev console — helpers loaded from .iex.exs

  fixture(extra \\\\ [])         map declaration; appends extra {name, spec} tuples
  schema(extra \\\\ %{})         JSON Schema declaration; merges extra string-keyed properties
  ui_hints()                   UI-hints document for schema/0 (order, group, widget/help)
  pump_inspection()            {schema, ui} of the end-to-end example, from the fixture files
  compile!(decl \\\\ fixture())  compile (adapter auto-detected), print diagnostics, return %Definition{}

  Try: compile!(schema(), ui: ui_hints()) |> Info.fields() |> Enum.map(&{&1.name, &1.role})
  Try: {s, ui} = pump_inspection(); compile!(s, ui: ui) |> Info.origins(["notes"])
""")
