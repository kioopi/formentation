defmodule Formentation.DefinitionTest do
  use ExUnit.Case, async: true

  alias Formentation.Definition

  test "root is an enforced key" do
    assert_raise ArgumentError, fn ->
      struct!(Definition, diagnostics: [])
    end
  end
end
