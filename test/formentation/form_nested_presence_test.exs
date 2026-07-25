defmodule Formentation.FormNestedPresenceTest do
  use ExUnit.Case, async: true

  alias Formentation.{Form, Issue}

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

  describe "required nested objects (JSON Schema)" do
    test "a required absent object stays absent and reports :required at its own path" do
      form =
        address_schema(address_required: true, street_required: true)
        |> Form.new(%{"title" => "Old"})
        |> Form.submit(%{"title" => "New"})

      assert {:ok, candidate} = Form.candidate(form)
      refute Map.has_key?(candidate, "address")

      assert [%Issue{code: :required}] = Form.issues(form, ["address"])
      assert Form.issues(form, ["address", "street"]) == []
    end

    test "the required group issue exists in both events but is only visible on submit (D-014)" do
      definition = address_schema(address_required: true, street_required: true)

      changed = Form.validate(Form.new(definition, %{"title" => "Old"}), %{"title" => "New"})
      submitted = Form.submit(Form.new(definition, %{"title" => "Old"}), %{"title" => "New"})

      # The group-level :required issue is produced regardless of event, at the
      # group path and no child path — so the gate below is gating a real issue.
      for form <- [changed, submitted] do
        assert [%Issue{code: :required}] = Form.issues(form, ["address"])
        assert Form.issues(form, ["address", "street"]) == []
      end

      # ...but D-014 hides it on :change and reveals it on :submit.
      refute Form.show_issues?(changed, ["address"])
      assert Form.show_issues?(submitted, ["address"])
    end

    test "clearing all typed children removes a required object; :required lands at the group path" do
      form =
        address_schema(address_required: true, street_required: false)
        |> Form.new(%{"address" => %{"house_number" => 4}})
        |> Form.submit(%{"address" => %{"house_number" => ""}})

      assert {:ok, candidate} = Form.candidate(form)
      refute Map.has_key?(candidate, "address")

      assert [%Issue{code: :required}] = Form.issues(form, ["address"])
      assert Form.issues(form, ["address", "house_number"]) == []
    end

    test "a submitted valid child creates the object using decoded values" do
      form =
        address_schema(address_required: true, street_required: false)
        |> Form.new(%{})
        |> Form.submit(%{"address" => %{"house_number" => "4"}})

      assert Form.candidate(form) == {:ok, %{"address" => %{"house_number" => 4}}}
      assert Form.issues(form, ["address"]) == []
    end
  end
end
