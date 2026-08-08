defmodule Formentation.Phoenix.BoundaryTest do
  use ExUnit.Case, async: true

  # D-017: the core compiles without Phoenix; only lib/formentation/phoenix
  # may reference Phoenix modules.

  @lib Path.expand("../../../lib", __DIR__)

  test "no module outside Formentation.Phoenix references Phoenix" do
    offenders =
      for file <- Path.wildcard(Path.join(@lib, "**/*.ex")),
          not String.starts_with?(file, Path.join(@lib, "formentation/phoenix/")),
          references_phoenix?(file),
          do: Path.relative_to(file, @lib)

    assert offenders == []
  end

  test "Phoenix integration does not branch on the mixed data-nesting flag" do
    offenders =
      for file <- Path.wildcard(Path.join(@lib, "formentation/phoenix/**/*.ex")),
          file |> File.read!() |> String.contains?("nests_data?"),
          do: Path.relative_to(file, @lib)

    assert offenders == []
  end

  test "production code does not depend on mixed definition storage" do
    offenders =
      for file <- Path.wildcard(Path.join(@lib, "formentation/**/*.ex")),
          file |> File.read!() |> legacy_mixed_storage_reference?(),
          do: Path.relative_to(file, @lib)

    assert offenders == []
  end

  # Context owns the native-vs-generic entry branch, so Render.Preparation has
  # no reason to consult ProjectedForm directly any more.
  test "Render.Preparation reaches ProjectedForm only through Context" do
    source = File.read!(Path.join(@lib, "formentation/phoenix/render/preparation.ex"))

    refute String.contains?(source, "ProjectedForm")
  end

  # D-045's headline invariant: Context answers "which projection are we in"
  # and owns the cursor, but never builds a Phoenix form. cursor_to/2 returns
  # a descent distance and enter/2 returns a child segment precisely so the
  # descending stays in Render.Preparation. A text scan cannot state this —
  # context.ex names FormData in five doctest setups and one error message —
  # so match on the alias in the AST, where docstrings and error copy are
  # inert literals and only real code counts. Same mechanism as
  # references_phoenix?/1 above, narrowed to one module.
  test "Context never depends on Phoenix.HTML.FormData" do
    file = Path.join(@lib, "formentation/phoenix/render/preparation/context.ex")

    refute references_form_data?(file)
  end

  # The bare-name patterns `%Node.` and `Node.(Field|Group|Unsupported)` used
  # to stand in for the aliased legacy `Formentation.Node` struct. Since that
  # module no longer exists, and `Formentation.Phoenix.Render.Node` is now
  # aliased to the bare name `Node` by design (Task 5), a bare-usage match
  # would false-positive on the sanctioned module. The guard now detects the
  # legacy *alias* itself instead of legacy-looking *usage*: a bare `Node`
  # can only mean the removed struct if something aliased it, either as
  # `alias Formentation.Node` (first clause) or inside a brace-collapsed
  # `alias Formentation.{..., Node, ...}` (second clause) — the fully
  # qualified pattern alone would miss the brace form.
  defp legacy_mixed_storage_reference?(source) do
    Regex.match?(~r/\bFormentation\.Node\b/, source) or
      Regex.match?(~r/alias\s+Formentation\.\{[^}]*\bNode\b/, source) or
      String.contains?(source, ["nests_data?", "stamp_declaration_order", "definition.root"]) or
      String.contains?(source, "%Definition{root:")
  end

  defp references_form_data?(file) do
    {:ok, ast} = file |> File.read!() |> Code.string_to_quoted()

    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {:__aliases__, _, [:Phoenix, :HTML, :FormData]} = node, _acc -> {node, true}
        {:__aliases__, _, [:FormData | _]} = node, _acc -> {node, true}
        node, acc -> {node, acc}
      end)

    found?
  end

  defp references_phoenix?(file) do
    {:ok, ast} = file |> File.read!() |> Code.string_to_quoted()

    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {:__aliases__, _, [:Phoenix | _]} = node, _acc -> {node, true}
        node, acc -> {node, acc}
      end)

    found?
  end
end
