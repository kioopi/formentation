defmodule Formentation.JSONPointerTest do
  use ExUnit.Case, async: true

  alias Formentation.JSONPointer

  doctest Formentation.JSONPointer

  test "joins segments into an RFC 6901 pointer" do
    assert JSONPointer.join([]) == ""
    assert JSONPointer.join(["properties", "notes", "title"]) == "/properties/notes/title"
  end

  test "escapes ~ and / inside segments" do
    assert JSONPointer.join(["a/b"]) == "/a~1b"
    assert JSONPointer.join(["a~b"]) == "/a~0b"
    assert JSONPointer.escape_segment("~/") == "~0~1"
  end

  test "escaping order does not double-escape" do
    # "/" must become "~1", never "~01"
    assert JSONPointer.escape_segment("/") == "~1"
  end
end
