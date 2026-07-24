defmodule Formentation.NodeIdTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Formentation.{NodeId, TemplatePath}

  doctest Formentation.NodeId

  test "the root path has id /" do
    assert NodeId.from_path(%TemplatePath{segments: []}) == "/"
  end

  test "plain segments join with /" do
    assert NodeId.from_path(%TemplatePath{segments: ["dimensions", "width"]}) ==
             "/dimensions/width"
  end

  test "segments containing the id vocabulary are escaped" do
    assert NodeId.from_path(%TemplatePath{segments: ["a/b"]}) == "/a~1b"
    assert NodeId.from_path(%TemplatePath{segments: ["#electrical"]}) == "/~2electrical"
    assert NodeId.from_path(%TemplatePath{segments: ["a~b"]}) == "/a~0b"
  end

  test "group ids append after # with escaping" do
    assert NodeId.group(%TemplatePath{segments: []}, "electrical") == "/#electrical"
    assert NodeId.group(%TemplatePath{segments: ["engine"]}, "el#1") == "/engine#el~21"
  end

  test "a property named like a group id no longer collides" do
    field_id = NodeId.from_path(%TemplatePath{segments: ["#electrical"]})
    group_id = NodeId.group(%TemplatePath{segments: []}, "electrical")
    refute field_id == group_id
  end

  property "distinct segment lists produce distinct ids" do
    segment = StreamData.string(:printable, min_length: 1, max_length: 8)

    check all(
            left <- StreamData.list_of(segment, min_length: 1, max_length: 4),
            right <- StreamData.list_of(segment, min_length: 1, max_length: 4),
            left != right
          ) do
      refute NodeId.from_path(%TemplatePath{segments: left}) ==
               NodeId.from_path(%TemplatePath{segments: right})
    end
  end

  property "escaping round-trips" do
    check all(segment <- StreamData.string(:printable, min_length: 1, max_length: 16)) do
      unescaped =
        segment
        |> NodeId.escape_segment()
        |> String.replace("~2", "#")
        |> String.replace("~1", "/")
        |> String.replace("~0", "~")

      assert unescaped == segment
    end
  end
end
