defmodule Formentation.SubmissionBlockerTest do
  use ExUnit.Case, async: true

  alias Formentation.{InstancePath, SubmissionBlocker}

  test "builds with enforced keys and an empty issues default" do
    blocker = %SubmissionBlocker{
      path: InstancePath.new!(["tags"]),
      node_id: "/tags",
      code: :unsupported_required,
      message: "cannot be supplied"
    }

    assert blocker.issues == []
    assert blocker.code == :unsupported_required
  end

  test "raises when an enforced key is missing" do
    assert_raise ArgumentError, fn ->
      # `code` and `message` omitted
      struct!(SubmissionBlocker, path: InstancePath.new!(["tags"]), node_id: "/tags")
    end
  end
end
