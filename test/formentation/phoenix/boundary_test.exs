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
