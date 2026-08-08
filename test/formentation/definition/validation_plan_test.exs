defmodule Formentation.Definition.ValidationPlanTest do
  use ExUnit.Case, async: true

  alias Formentation.Definition.ValidationPlan

  doctest Formentation.Definition.ValidationPlan

  test "carries an executable module and an opaque artifact" do
    plan = %ValidationPlan{module: List, artifact: {:opaque, 1}}
    assert plan.module == List
    assert plan.artifact == {:opaque, 1}
  end

  test "both keys are enforced" do
    assert_raise ArgumentError, fn -> struct!(ValidationPlan, %{}) end
  end
end
