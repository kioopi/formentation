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

  describe "child/2" do
    test "appends a string segment" do
      path = InstancePath.new!(["addresses"])
      assert InstancePath.child(path, "street") == InstancePath.new!(["addresses", "street"])
    end

    test "appends an integer index" do
      path = InstancePath.new!(["addresses"])
      assert InstancePath.child(path, 0) == InstancePath.new!(["addresses", 0])
    end

    test "rejects an invalid segment" do
      assert_raise ArgumentError, fn ->
        InstancePath.child(InstancePath.new!([]), :item)
      end
    end
  end

  describe "parent/1" do
    test "drops the last segment" do
      assert InstancePath.parent(InstancePath.new!(["addresses", 0, "street"])) ==
               InstancePath.new!(["addresses", 0])
    end

    test "root stays root" do
      assert InstancePath.parent(InstancePath.new!([])) == InstancePath.new!([])
    end
  end

  describe "to_template/1" do
    test "replaces integer segments with :item" do
      assert InstancePath.new!(["addresses", 0, "street"]) |> InstancePath.to_template() ==
               Formentation.TemplatePath.new!(["addresses", :item, "street"])
    end

    test "a string segment named like a number stays a string" do
      assert InstancePath.new!(["0"]) |> InstancePath.to_template() ==
               Formentation.TemplatePath.new!(["0"])
    end
  end

  describe "ancestor_or_self?/2" do
    test "a path is its own ancestor" do
      p = InstancePath.new!(["tags"])
      assert InstancePath.ancestor_or_self?(p, p)
    end

    test "a strict ancestor of a descendant is true (including index descendants)" do
      assert InstancePath.ancestor_or_self?(
               InstancePath.new!(["tags"]),
               InstancePath.new!(["tags", 0])
             )

      assert InstancePath.ancestor_or_self?(
               InstancePath.new!([]),
               InstancePath.new!(["anything"])
             )
    end

    test "segment comparison, not string prefix" do
      refute InstancePath.ancestor_or_self?(
               InstancePath.new!(["tag"]),
               InstancePath.new!(["tags"])
             )
    end

    test "a descendant is not an ancestor of its ancestor; unrelated paths are false" do
      refute InstancePath.ancestor_or_self?(
               InstancePath.new!(["tags", 0]),
               InstancePath.new!(["tags"])
             )

      refute InstancePath.ancestor_or_self?(
               InstancePath.new!(["a"]),
               InstancePath.new!(["b"])
             )
    end

    test "an integer segment does not equal its string form" do
      refute InstancePath.ancestor_or_self?(
               InstancePath.new!(["tags", 0]),
               InstancePath.new!(["tags", "0"])
             )
    end
  end
end
