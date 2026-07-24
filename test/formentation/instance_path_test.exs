defmodule Formentation.InstancePathTest do
  use ExUnit.Case, async: true

  alias Formentation.InstancePath

  doctest Formentation.InstancePath

  test "new!/1 accepts string and non-negative integer segments" do
    assert %InstancePath{segments: ["addresses", 2, "postcode"]} =
             InstancePath.new!(["addresses", 2, "postcode"])
  end

  test "new!/1 rejects atoms and negative integers" do
    assert_raise ArgumentError, fn -> InstancePath.new!([:postcode]) end
    assert_raise ArgumentError, fn -> InstancePath.new!(["addresses", -1]) end
  end
end
