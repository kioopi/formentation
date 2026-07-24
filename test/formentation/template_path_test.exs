defmodule Formentation.TemplatePathTest do
  use ExUnit.Case, async: true

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
end
