defmodule Formentation.Phoenix.Render.Plan.SummaryEntryTest do
  use ExUnit.Case, async: true

  doctest Formentation.Phoenix.Render.Plan.SummaryEntry

  alias Formentation.Phoenix.Render.Plan.SummaryEntry

  describe "from_target/2" do
    test "ignores keys the target carries beyond id and label" do
      target = %{id: "email", label: "Email", widget: :email_input}

      assert SummaryEntry.from_target(target, "is required") ==
               %SummaryEntry{id: "email", label: "Email", message: "is required"}
    end
  end

  describe "the struct" do
    test "requires a message" do
      assert_raise ArgumentError, fn ->
        struct!(SummaryEntry, id: "email", label: "Email")
      end
    end
  end
end
