defmodule Formentation.FormNestedPresenceTest do
  use ExUnit.Case, async: true

  import Formentation.Test.FormHelpers

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
        |> submitted_form(%{"title" => "New"})

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
        |> submitted_form(%{"title" => "New"})

      assert {:ok, candidate} = Form.candidate(form)
      refute Map.has_key?(candidate, "address")

      assert [%Issue{code: :required}] = Form.issues(form, ["address"])
      assert Form.issues(form, ["address", "street"]) == []
    end

    test "the required group issue exists in both events but is only visible on submit (D-014)" do
      definition = address_schema(address_required: true, street_required: true)

      changed = Form.validate(Form.new(definition, %{"title" => "Old"}), %{"title" => "New"})
      submitted = submitted_form(Form.new(definition, %{"title" => "Old"}), %{"title" => "New"})

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
        |> submitted_form(%{"address" => %{"house_number" => ""}})

      assert {:ok, candidate} = Form.candidate(form)
      refute Map.has_key?(candidate, "address")

      assert [%Issue{code: :required}] = Form.issues(form, ["address"])
      assert Form.issues(form, ["address", "house_number"]) == []
    end

    test "a submitted valid child creates the object using decoded values" do
      form =
        address_schema(address_required: true, street_required: false)
        |> Form.new(%{})
        |> submitted_form(%{"address" => %{"house_number" => "4"}})

      assert Form.candidate(form) == {:ok, %{"address" => %{"house_number" => 4}}}
      assert Form.issues(form, ["address"]) == []
    end
  end

  # dimensions.{width:int, label:string}; optional at root.
  defp box_definition do
    compile_map(%{
      kind: :object,
      properties: [
        {"title", %{kind: :string}},
        {"dimensions",
         %{
           kind: :object,
           properties: [
             {"width", %{kind: :integer}},
             {"label", %{kind: :string}}
           ]
         }}
      ]
    })
  end

  # dimensions.{width:int (editable), sku:string (read_only), attachment:file (unsupported)}
  defp preserving_box_definition do
    compile_map(%{
      kind: :object,
      properties: [
        {"dimensions",
         %{
           kind: :object,
           properties: [
             {"width", %{kind: :integer}},
             {"sku", %{kind: :string, read_only: true}},
             {"attachment", %{kind: :file}}
           ]
         }}
      ]
    })
  end

  # contact.address.width — three data-nesting levels.
  defp deep_definition do
    compile_map(%{
      kind: :object,
      properties: [
        {"contact",
         %{
           kind: :object,
           properties: [
             {"address", %{kind: :object, properties: [{"width", %{kind: :integer}}]}}
           ]
         }}
      ]
    })
  end

  # dimensions.width with a default, for the defaults test.
  defp defaulted_box_definition do
    compile_map(%{
      kind: :object,
      properties: [
        {"dimensions", %{kind: :object, properties: [{"width", %{kind: :integer, default: 7}}]}}
      ]
    })
  end

  defp compile_map(declaration) do
    {:ok, definition, _diagnostics} =
      Formentation.compile(declaration, adapter: Formentation.Source.Map)

    definition
  end

  describe "candidate shape (map source)" do
    test "a submitted typed child creates the object with decoded values" do
      form =
        box_definition()
        |> Form.new()
        |> submitted_form(%{"title" => "New", "dimensions" => %{"width" => "4"}})

      assert Form.candidate(form) == {:ok, %{"title" => "New", "dimensions" => %{"width" => 4}}}
    end

    test "an empty string is a surviving value and keeps its object (D-010)" do
      form =
        box_definition()
        |> Form.new()
        |> submitted_form(%{"dimensions" => %{"label" => "", "width" => ""}})

      assert {:ok, candidate} = Form.candidate(form)
      assert candidate["dimensions"] == %{"label" => ""}
    end

    test "clearing every typed child by explicit blank removes an optional object" do
      form =
        box_definition()
        |> Form.new(%{"dimensions" => %{"width" => 4}})
        |> submitted_form(%{"dimensions" => %{"width" => ""}})

      assert {:ok, candidate} = Form.candidate(form)
      refute Map.has_key?(candidate, "dimensions")
    end

    test "omitting an originally present child from the params removes its object" do
      # The other removal route: :not_provided -> :unset, rather than
      # {:provided, ""} -> :unset. The child is present in the original but
      # absent from the submitted params, so the group empties and drops.
      form =
        box_definition()
        |> Form.new(%{"dimensions" => %{"width" => 4}})
        |> submitted_form(%{})

      assert {:ok, candidate} = Form.candidate(form)
      refute Map.has_key?(candidate, "dimensions")
    end

    test "original unknown keys keep the object; submitted unknown keys do not create one" do
      kept =
        box_definition()
        |> Form.new(%{"dimensions" => %{"width" => 4, "legacy_identifier" => "A-17"}})
        |> submitted_form(%{"dimensions" => %{"width" => ""}})

      assert {:ok, candidate} = Form.candidate(kept)
      assert candidate["dimensions"] == %{"legacy_identifier" => "A-17"}

      ignored =
        box_definition()
        |> Form.new()
        |> submitted_form(%{"dimensions" => %{"unknown" => "x"}})

      assert Form.candidate(ignored) == {:ok, %{}}
    end

    test "read-only and unsupported descendants keep the object when editable children clear" do
      form =
        preserving_box_definition()
        |> Form.new(%{
          "dimensions" => %{"width" => 4, "sku" => "RO-1", "attachment" => ["a.png"]}
        })
        |> submitted_form(%{"dimensions" => %{"width" => ""}})

      assert {:ok, candidate} = Form.candidate(form)
      assert candidate["dimensions"] == %{"sku" => "RO-1", "attachment" => ["a.png"]}
    end

    test "invalid child input defers materialization without fabricating an object" do
      form =
        box_definition()
        |> Form.new()
        |> submitted_form(%{"dimensions" => %{"width" => "x"}})

      assert Form.candidate(form) == :none

      assert [%Issue{code: :invalid_integer, source: :decode}] =
               Form.issues(form, ["dimensions", "width"])

      assert Form.issues(form, ["dimensions"]) == []
    end

    test "presence is recursive: a surviving descendant creates every missing ancestor" do
      created =
        deep_definition()
        |> Form.new()
        |> submitted_form(%{"contact" => %{"address" => %{"width" => "4"}}})

      assert Form.candidate(created) ==
               {:ok, %{"contact" => %{"address" => %{"width" => 4}}}}

      neither =
        deep_definition()
        |> Form.new()
        |> submitted_form(%{})

      assert Form.candidate(neither) == {:ok, %{}}

      cleared =
        deep_definition()
        |> Form.new(%{"contact" => %{"address" => %{"width" => 4}}})
        |> submitted_form(%{"contact" => %{"address" => %{"width" => ""}}})

      assert Form.candidate(cleared) == {:ok, %{}}
    end

    test "defaults do not reappear on transitions or force object presence" do
      form =
        defaulted_box_definition()
        |> Form.new(%{}, defaults: :apply)
        |> submitted_form(%{})

      assert {:ok, candidate} = Form.candidate(form)
      refute Map.has_key?(candidate, "dimensions")
    end

    test "removes an empty nested object because Phase 1 has no group presence signal" do
      form =
        box_definition()
        |> Form.new(%{"dimensions" => %{}})
        |> submitted_form(%{})

      assert {:ok, candidate} = Form.candidate(form)
      refute Map.has_key?(candidate, "dimensions")
    end

    test "drops an originally-present non-object group value when no child survives (D-026)" do
      for original <- [%{"dimensions" => nil}, %{"dimensions" => "invalid"}] do
        form =
          box_definition()
          |> Form.new(original)
          |> submitted_form(%{})

        assert {:ok, candidate} = Form.candidate(form)
        refute Map.has_key?(candidate, "dimensions")
      end
    end
  end
end
