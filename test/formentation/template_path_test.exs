defmodule Formentation.TemplatePathTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Formentation.TemplatePath

  doctest Formentation.TemplatePath

  test "new!/1 accepts string segments and the :item marker" do
    assert %TemplatePath{segments: ["addresses", :item, "postcode"]} =
             TemplatePath.new!(["addresses", :item, "postcode"])
  end

  test "new!/1 rejects atom segments that are not :item" do
    assert_raise ArgumentError, fn -> TemplatePath.new!(["addresses", :postcode]) end
  end

  test "child/2 appends a string segment" do
    path = TemplatePath.new!(["dimensions"])
    assert %TemplatePath{segments: ["dimensions", "width"]} = TemplatePath.child(path, "width")
  end

  describe "item/1" do
    test "appends the :item marker" do
      assert TemplatePath.new!(["addresses"]) |> TemplatePath.item() ==
               TemplatePath.new!(["addresses", :item])
    end
  end

  describe "matches?/2" do
    test ":item matches any integer, strings match exactly" do
      template = TemplatePath.new!(["addresses", :item, "street"])

      assert TemplatePath.matches?(
               template,
               Formentation.InstancePath.new!(["addresses", 0, "street"])
             )

      assert TemplatePath.matches?(
               template,
               Formentation.InstancePath.new!(["addresses", 7, "street"])
             )

      refute TemplatePath.matches?(
               template,
               Formentation.InstancePath.new!(["addresses", "0", "street"])
             )

      refute TemplatePath.matches?(
               template,
               Formentation.InstancePath.new!(["addresses", 0, "city"])
             )
    end

    test "lengths must agree" do
      template = TemplatePath.new!(["addresses", :item])
      refute TemplatePath.matches?(template, Formentation.InstancePath.new!(["addresses"]))

      refute TemplatePath.matches?(
               template,
               Formentation.InstancePath.new!(["addresses", 0, "street"])
             )
    end

    property "matches?/2 agrees with to_template/1 equality" do
      check all(
              segments <-
                StreamData.list_of(
                  StreamData.one_of([
                    StreamData.string(:alphanumeric, min_length: 1),
                    StreamData.non_negative_integer()
                  ]),
                  max_length: 6
                )
            ) do
        instance = Formentation.InstancePath.new!(segments)
        template = Formentation.InstancePath.to_template(instance)
        assert TemplatePath.matches?(template, instance)
      end
    end
  end
end
