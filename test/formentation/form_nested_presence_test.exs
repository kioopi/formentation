defmodule Formentation.FormNestedPresenceTest do
  use ExUnit.Case, async: true

  alias Formentation.Form

  # A JSON Schema definition carrying a real ValidationPlan, so the
  # validator's path-mapping (missing required object -> group path;
  # present object missing required child -> child path) is exercised.
  # `title` is an unrelated sibling; `address` is optional/required by
  # opts; `street` (string) is address's required-by-opts child;
  # `house_number` (integer) is an always-optional typed child.
  defp address_schema(opts) do
    address_required = Keyword.get(opts, :address_required, false)
    street_required = Keyword.get(opts, :street_required, true)

    schema = %{
      "type" => "object",
      "required" => if(address_required, do: ["address"], else: []),
      "properties" => %{
        "title" => %{"type" => "string"},
        "address" => %{
          "type" => "object",
          "required" => if(street_required, do: ["street"], else: []),
          "properties" => %{
            "street" => %{"type" => "string"},
            "house_number" => %{"type" => "integer"}
          }
        }
      }
    }

    {:ok, definition, _diagnostics} =
      Formentation.compile(schema, adapter: Formentation.JSONSchema)

    definition
  end

  describe "optional nested objects (JSON Schema)" do
    test "an optional absent object stays absent after an unrelated transition (issue #1 regression)" do
      form =
        address_schema(address_required: false, street_required: true)
        |> Form.new(%{"title" => "Old"})
        |> Form.submit(%{"title" => "New"})

      assert Form.candidate(form) == {:ok, %{"title" => "New"}}
      assert Form.issues(form, ["address"]) == []
      assert Form.issues(form, ["address", "street"]) == []
    end
  end
end
