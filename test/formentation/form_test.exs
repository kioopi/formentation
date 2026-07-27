defmodule Formentation.FormTest do
  use ExUnit.Case, async: true

  alias Formentation.Fixtures.PumpInspection
  alias Formentation.{Form, InstancePath, Issue, Params}
  alias Formentation.Form.FieldState

  doctest Formentation.Form

  defp pump_definition do
    {:ok, definition, []} =
      Formentation.compile(PumpInspection.map_source(), adapter: Formentation.Source.Map)

    definition
  end

  defp json_pump_definition do
    {:ok, definition, []} =
      Formentation.compile(PumpInspection.json_schema(),
        adapter: Formentation.JSONSchema,
        ui: PumpInspection.ui_hints()
      )

    definition
  end

  describe "new/3" do
    test "wraps the original data untouched, with the candidate equal to it" do
      data = %{"serial_number" => "PX-2044", "operating_hours" => 5102}
      form = Form.new(pump_definition(), data)

      assert form.original == data
      assert Form.candidate(form) == {:ok, data}
      assert form.action == nil
      assert form.params == nil
      assert Form.issues(form) == []
    end

    test "defaults to empty data" do
      assert Form.new(pump_definition()).original == %{}
    end
  end

  describe "new/3 defaults" do
    defp defaults_definition do
      declaration = %{
        kind: :object,
        properties: [
          {"priority", %{kind: :string, default: "normal"}},
          {"notes", %{kind: :string}},
          {"meta",
           %{
             kind: :object,
             properties: [{"revision", %{kind: :integer, default: 1}}]
           }},
          {"empty_group",
           %{
             kind: :object,
             properties: [{"plain", %{kind: :string}}]
           }}
        ]
      }

      {:ok, definition, []} = Formentation.compile(declaration, adapter: Formentation.Source.Map)
      definition
    end

    test "defaults: :apply fills absent keys, creating nested objects when needed" do
      form = Form.new(defaults_definition(), %{}, defaults: :apply)

      assert form.original == %{"priority" => "normal", "meta" => %{"revision" => 1}}

      assert Form.candidate(form) ==
               {:ok, %{"priority" => "normal", "meta" => %{"revision" => 1}}}
    end

    test "provided keys are never overwritten" do
      form =
        Form.new(defaults_definition(), %{"priority" => "high", "meta" => %{"revision" => 7}},
          defaults: :apply
        )

      assert form.original["priority"] == "high"
      assert form.original["meta"] == %{"revision" => 7}
    end

    test "without the flag, data is taken as-is" do
      assert Form.new(defaults_definition(), %{}).original == %{}
    end

    test "a present nil value at a nesting key is left untouched, not coerced to a map" do
      form = Form.new(defaults_definition(), %{"meta" => nil}, defaults: :apply)

      assert form.original["meta"] == nil
    end

    test "a present non-map value at a group with no defaults of its own is left untouched" do
      form = Form.new(defaults_definition(), %{"empty_group" => "junk"}, defaults: :apply)

      assert form.original["empty_group"] == "junk"
    end

    test "defaults apply through presentation groups that don't nest data" do
      declaration = %{
        kind: :object,
        properties: [{"priority", %{kind: :string, default: "normal"}}],
        groups: [%{id: "g", fields: ["priority"]}]
      }

      {:ok, definition, []} = Formentation.compile(declaration, adapter: Formentation.Source.Map)

      form = Form.new(definition, %{}, defaults: :apply)

      assert form.original == %{"priority" => "normal"}
    end

    test "a replace transition that clears a defaulted field does not resurrect it" do
      form =
        defaults_definition()
        |> Form.new(%{}, defaults: :apply)
        |> Form.transition(%Formentation.Params{values: %{}})

      assert {:ok, candidate} = Form.candidate(form)
      refute Map.has_key?(candidate, "priority")
    end
  end

  describe "field/2" do
    test "a pristine field has no transport, a keep operation, and unknown usage" do
      form = Form.new(pump_definition(), %{"serial_number" => "PX-2044"})

      assert %FieldState{
               transport: :not_provided,
               operation: :keep,
               usage: :unknown,
               issues: [],
               display_value: "PX-2044"
             } = Form.field(form, ["serial_number"])
    end

    test "display encodes scalars for display" do
      data = %{"operating_hours" => 5102, "voltage" => 230.1, "insulation_ok" => true}
      form = Form.new(pump_definition(), data)

      assert Form.field(form, ["operating_hours"]).display_value == "5102"
      assert Form.field(form, ["voltage"]).display_value == "230.1"
      assert Form.field(form, ["insulation_ok"]).display_value == "true"
      assert Form.field(form, ["notes"]).display_value == ""
    end
  end

  describe "usage/2" do
    test "unknown by default" do
      assert Form.usage(Form.new(pump_definition()), ["notes"]) == :unknown
    end
  end

  describe "field/2 display derivation" do
    test "a provided binary raw shows verbatim, even when decoding failed" do
      path = InstancePath.new!(["operating_hours"])

      issue = %Issue{
        path: path,
        code: :invalid_integer,
        message: ~s("51o2" is not a valid integer),
        source: :decode
      }

      form = %{
        Form.new(pump_definition(), %{"operating_hours" => 5102})
        | transports: %{path => {:provided, "51o2"}},
          operations: %{path => {:invalid, issue}}
      }

      state = Form.field(form, ["operating_hours"])
      assert state.display_value == "51o2"
      assert state.operation == {:invalid, issue}
    end

    test "a provided native value is encoded for display" do
      path = InstancePath.new!(["operating_hours"])

      form = %{
        Form.new(pump_definition())
        | transports: %{path => {:provided, 42}},
          operations: %{path => {:set, 42}}
      }

      assert Form.field(form, ["operating_hours"]).display_value == "42"
    end

    test "an unset field displays empty even when the original had a value" do
      path = InstancePath.new!(["notes"])
      form = %{Form.new(pump_definition(), %{"notes" => "old"}) | operations: %{path => :unset}}

      assert Form.field(form, ["notes"]).display_value == ""
    end
  end

  describe "stored issues and usage" do
    test "issues/2 returns the stored issues for a path" do
      path = InstancePath.new!(["notes"])
      issue = %Issue{path: path, code: :invalid_value, message: "nope", source: :decode}
      form = %{Form.new(pump_definition()) | issues: %{path => [issue]}}

      assert Form.issues(form, ["notes"]) == [issue]
      assert Form.issues(form) == [issue]
      assert Form.field(form, ["notes"]).issues == [issue]
    end

    test "usage/2 returns stored used and unused states" do
      used = InstancePath.new!(["notes"])
      unused = InstancePath.new!(["voltage"])
      form = %{Form.new(pump_definition()) | usage: %{used => :used, unused => :unused}}

      assert Form.usage(form, ["notes"]) == :used
      assert Form.usage(form, ["voltage"]) == :unused
    end
  end

  describe "transition/2 envelope" do
    test "rejects patch mode — reserved (D-013)" do
      form = Form.new(pump_definition())

      assert_raise ArgumentError, ~r/patch/, fn ->
        Form.transition(form, %Params{values: %{}, mode: :patch})
      end
    end

    test "rejects non-root scope — reserved (spec decision 7)" do
      form = Form.new(pump_definition())

      assert_raise ArgumentError, ~r/scope/, fn ->
        Form.transition(form, %Params{values: %{}, scope: ["nested"]})
      end
    end

    test "rejects non-map values" do
      form = Form.new(pump_definition())

      assert_raise ArgumentError, ~r/values/, fn ->
        Form.transition(form, %Params{values: "oops"})
      end
    end
  end

  describe "validate/2 and submit/2" do
    test "validate/2 applies a :change replace transition" do
      form = Form.new(json_pump_definition())
      form = Form.validate(form, %{"operating_hours" => "4800"})

      assert form.action == :change
      assert {:ok, %{"operating_hours" => 4800}} = Form.candidate(form)
    end

    test "submit/2 applies a :submit replace transition and returns the decision tuple" do
      form = Form.new(json_pump_definition())
      assert {:error, form} = Form.submit(form, %{"operating_hours" => "51o2"})

      assert form.action == :submit
      assert Form.candidate(form) == :none
      assert [%Formentation.Issue{}] = Form.issues(form, ["operating_hours"])
    end
  end

  describe "transition/2 decoding" do
    test "decodes every provided field per its value type" do
      values = %{
        "serial_number" => "PX-2044",
        "condition" => "good",
        "last_service" => "2026-06-30",
        "operating_hours" => "5102",
        "voltage" => "230.1",
        "insulation_ok" => "true",
        "notes" => ""
      }

      form = Form.transition(Form.new(pump_definition()), %Params{values: values})

      assert Form.candidate(form) ==
               {:ok,
                %{
                  "serial_number" => "PX-2044",
                  "condition" => "good",
                  "last_service" => "2026-06-30",
                  "operating_hours" => 5102,
                  "voltage" => 230.1,
                  "insulation_ok" => true,
                  "notes" => ""
                }}

      assert form.action == :change
      assert form.params == values
      assert Form.field(form, ["operating_hours"]).operation == {:set, 5102}
      assert Form.field(form, ["notes"]).operation == {:set, ""}
    end

    test "clearing a date-role field decodes to {:set, \"\"}, not :unset (D-010 amendment)" do
      values = %{"serial_number" => "PX-2044", "condition" => "good", "last_service" => ""}
      form = Form.transition(Form.new(pump_definition()), %Params{values: values})

      assert Form.field(form, ["last_service"]).operation == {:set, ""}
      assert {:ok, candidate} = Form.candidate(form)
      assert candidate["last_service"] == ""
    end

    test "absent keys within the replace scope unset (D-010/D-013)" do
      original = %{"serial_number" => "PX-2044", "notes" => "old"}

      form =
        Form.transition(Form.new(pump_definition(), original), %Params{
          values: %{"serial_number" => "PX-2044"}
        })

      assert Form.field(form, ["notes"]).operation == :unset
      assert Form.field(form, ["notes"]).transport == :not_provided
      assert {:ok, candidate} = Form.candidate(form)
      refute Map.has_key?(candidate, "notes")
    end

    test "a failed decode blocks the candidate and preserves raw input (D-009/D-012)" do
      values = %{"serial_number" => "PX-2044", "operating_hours" => "51o2"}
      form = Form.transition(Form.new(pump_definition()), %Params{values: values})

      assert Form.candidate(form) == :none

      assert %Formentation.Form.FieldState{
               transport: {:provided, "51o2"},
               operation: {:invalid, %Issue{code: :invalid_integer}},
               display_value: "51o2"
             } = Form.field(form, ["operating_hours"])

      assert [%Issue{code: :invalid_integer, source: :decode}] =
               Form.issues(form, ["operating_hours"])
    end

    test "the submit event becomes the action" do
      form = Form.transition(Form.new(pump_definition()), %Params{values: %{}, event: :submit})
      assert form.action == :submit
    end

    test "the input form is not changed" do
      form = Form.new(pump_definition(), %{"notes" => "old"})
      snapshot = form
      _next = Form.transition(form, %Params{values: %{}})
      assert form == snapshot
    end
  end

  describe "transition/2 nested and edge materialization" do
    defp nested_definition do
      declaration = %{
        kind: :object,
        properties: [
          {"title", %{kind: :string}},
          {"dimensions",
           %{
             kind: :object,
             properties: [
               {"width", %{kind: :integer}},
               {"height", %{kind: :integer}}
             ]
           }}
        ]
      }

      {:ok, definition, []} = Formentation.compile(declaration, adapter: Formentation.Source.Map)
      definition
    end

    test "nested objects decode by path and materialize as maps" do
      values = %{"title" => "Box", "dimensions" => %{"width" => "4"}}
      form = Form.transition(Form.new(nested_definition()), %Params{values: values})

      assert Form.candidate(form) == {:ok, %{"title" => "Box", "dimensions" => %{"width" => 4}}}
      assert Form.field(form, ["dimensions", "width"]).operation == {:set, 4}
      assert Form.field(form, ["dimensions", "height"]).operation == :unset
    end

    test "data-nesting groups with no surviving child are absent (D-026)" do
      form = Form.transition(Form.new(nested_definition()), %Params{values: %{}})
      assert Form.candidate(form) == {:ok, %{}}
    end

    test "keys the definition does not describe are preserved from the original" do
      form =
        Form.transition(
          Form.new(nested_definition(), %{"legacy" => true, "title" => "Old"}),
          %Params{values: %{}}
        )

      assert Form.candidate(form) == {:ok, %{"legacy" => true}}
    end

    test "unsupported nodes keep their original values and never decode" do
      declaration = %{
        kind: :object,
        properties: [
          {"title", %{kind: :string}},
          {"attachments", %{kind: :file}}
        ]
      }

      {:ok, definition, [_unsupported_warning]} =
        Formentation.compile(declaration, adapter: Formentation.Source.Map)

      form =
        Form.transition(
          Form.new(definition, %{"attachments" => ["a.png"]}),
          %Params{values: %{"title" => "T", "attachments" => "ignored"}}
        )

      assert Form.candidate(form) == {:ok, %{"title" => "T", "attachments" => ["a.png"]}}
    end
  end

  describe "transition/2 usage" do
    test "usage follows the unused markers of the snapshot" do
      values = %{"serial_number" => "PX", "notes" => "", "_unused_notes" => ""}
      form = Form.transition(Form.new(pump_definition()), %Params{values: values})

      assert Form.usage(form, ["serial_number"]) == :used
      assert Form.usage(form, ["notes"]) == :unused
      assert Form.usage(form, ["voltage"]) == :unknown
    end

    test "paths absent from the snapshot keep their previous usage" do
      first = %Params{values: %{"serial_number" => "PX"}}
      second = %Params{values: %{"notes" => "hello"}}

      form =
        Form.new(pump_definition())
        |> Form.transition(first)
        |> Form.transition(second)

      assert Form.usage(form, ["serial_number"]) == :used
      assert Form.usage(form, ["notes"]) == :used
    end

    test "without markers usage degrades honestly, not to fabricated unused" do
      form = Form.transition(Form.new(pump_definition()), %Params{values: %{"notes" => ""}})

      assert Form.usage(form, ["notes"]) == :used
      assert Form.usage(form, ["serial_number"]) == :unknown
    end
  end

  describe "schema validation" do
    test "new/3 validates the initial data immediately" do
      form = Form.new(json_pump_definition(), %{})

      codes = form |> Form.issues() |> Enum.map(& &1.code)
      assert :required in codes
      assert [%Issue{code: :required, source: :validation}] = Form.issues(form, ["serial_number"])
    end

    test "map-source forms have no schema validation (validator is nil)" do
      assert Form.issues(Form.new(pump_definition(), %{})) == []
    end

    test "a schema whose validator failed to build also skips schema validation" do
      schema = %{
        "type" => "object",
        "properties" => %{"a" => %{"$ref" => "#/$defs/missing"}}
      }

      {:ok, definition, diagnostics} =
        Formentation.compile(schema, adapter: Formentation.JSONSchema)

      assert Enum.any?(diagnostics, &(&1.code == :validator_unavailable))
      assert definition.validation == nil
      assert Form.issues(Form.new(definition, %{})) == []
    end

    test "a clean candidate validates whole-instance" do
      values = %{"serial_number" => "PX", "condition" => "good"}
      form = Form.transition(Form.new(json_pump_definition()), %Params{values: values})

      assert [%Issue{code: :minLength, source: :validation}] =
               Form.issues(form, ["serial_number"])
    end

    test "the 51o2 walkthrough: any decode failure defers all schema validation (D-012)" do
      broken =
        Form.transition(Form.new(json_pump_definition()), %Params{
          values: %{"serial_number" => "PX", "operating_hours" => "51o2"}
        })

      assert Form.candidate(broken) == :none
      assert Enum.all?(Form.issues(broken), &(&1.source == :decode))
      assert [%Issue{code: :invalid_integer}] = Form.issues(broken, ["operating_hours"])
      assert Form.issues(broken, ["serial_number"]) == []
      assert Form.field(broken, ["operating_hours"]).display_value == "51o2"

      fixed =
        Form.transition(broken, %Params{
          values: %{
            "serial_number" => "PX",
            "condition" => "good",
            "operating_hours" => "5102"
          }
        })

      assert {:ok, %{"operating_hours" => 5102}} = Form.candidate(fixed)

      assert [%Issue{code: :minLength, source: :validation}] =
               Form.issues(fixed, ["serial_number"])

      assert Form.issues(fixed, ["operating_hours"]) == []
    end
  end

  describe "show_issues?/2" do
    test "pristine: stored issues stay hidden" do
      form = Form.new(json_pump_definition(), %{})

      assert Form.issues(form, ["serial_number"]) != []
      refute Form.show_issues?(form, ["serial_number"])
    end

    test "editing: hidden while unused, shown once used" do
      unused =
        Form.transition(Form.new(json_pump_definition()), %Params{
          values: %{"serial_number" => "", "_unused_serial_number" => "", "condition" => "good"}
        })

      assert Form.issues(unused, ["serial_number"]) != []
      refute Form.show_issues?(unused, ["serial_number"])

      used =
        Form.transition(Form.new(json_pump_definition()), %Params{
          values: %{"serial_number" => "", "condition" => "good"}
        })

      assert Form.show_issues?(used, ["serial_number"])
    end

    test "submit shows everything, used or not" do
      form =
        Form.transition(Form.new(json_pump_definition()), %Params{
          values: %{"serial_number" => "", "_unused_serial_number" => ""},
          event: :submit
        })

      assert Form.issues(form, ["serial_number"]) != []
      assert Form.show_issues?(form, ["serial_number"])
    end

    test "group and root issues show only on submit, even when usage propagated to used" do
      editing =
        Form.transition(Form.new(json_pump_definition()), %Params{
          values: %{"serial_number" => "PX-2044"}
        })

      refute Form.show_issues?(editing, [])

      submitted =
        Form.transition(Form.new(json_pump_definition()), %Params{
          values: %{"serial_number" => "PX-2044"},
          event: :submit
        })

      assert Form.show_issues?(submitted, [])
    end

    test "a used data-nesting group path stays hidden while editing, shown on submit" do
      editing =
        Form.transition(Form.new(nested_definition()), %Params{
          values: %{"dimensions" => %{"width" => "4"}}
        })

      assert Form.usage(editing, ["dimensions"]) == :used
      refute Form.show_issues?(editing, ["dimensions"])

      submitted =
        Form.transition(Form.new(nested_definition()), %Params{
          values: %{"dimensions" => %{"width" => "4"}},
          event: :submit
        })

      assert Form.show_issues?(submitted, ["dimensions"])
    end
  end

  describe "submitted?/1" do
    test "is false for a pristine form and after a :change transition" do
      definition = pump_definition()

      refute Form.submitted?(Form.new(definition))
      refute Form.submitted?(Form.validate(Form.new(definition), %{"serial_number" => "PX"}))
    end

    test "is true after submit/2" do
      definition = pump_definition()

      assert {:ok, _candidate, form} =
               Form.submit(Form.new(definition), %{"serial_number" => "PX"})

      assert Form.submitted?(form)
    end

    test "is true after an explicit :submit transition envelope" do
      form =
        Form.transition(Form.new(pump_definition()), %Formentation.Params{
          values: %{"serial_number" => "PX"},
          event: :submit
        })

      assert Form.submitted?(form)
    end
  end

  describe "per-kind node trees" do
    defp per_kind_definition do
      {:ok, definition, [_warning]} =
        Formentation.compile(
          %{
            kind: :object,
            properties: [
              {"priority", %{kind: :string, default: "normal"}},
              {"electrical",
               %{
                 kind: :object,
                 properties: [{"voltage", %{kind: :integer}}],
                 groups: [%{id: "power", fields: ["voltage"]}]
               }},
              {"gadget", %{kind: :file}}
            ]
          },
          adapter: Formentation.Source.Map
        )

      definition
    end

    test "defaults: :apply reads per-kind field and group nodes" do
      form = Form.new(per_kind_definition(), %{}, defaults: :apply)

      assert form.original == %{"priority" => "normal"}
    end

    test "transitions decode per-kind trees and preserve unsupported values" do
      form = Form.new(per_kind_definition(), %{"gadget" => %{"x" => 1}})

      params = %Params{
        values: %{"priority" => "high", "electrical" => %{"voltage" => "12"}},
        event: :change
      }

      form = Form.transition(form, params)

      assert Form.candidate(form) ==
               {:ok,
                %{
                  "priority" => "high",
                  "electrical" => %{"voltage" => 12},
                  "gadget" => %{"x" => 1}
                }}
    end

    test "show_issues?/2 consults per-kind field nodes for usage" do
      form = Form.new(per_kind_definition(), %{})
      form = Form.transition(form, %Params{values: %{"priority" => "high"}, event: :change})

      assert Form.show_issues?(form, ["priority"])
      refute Form.show_issues?(form, ["electrical"])
    end
  end

  describe "read-only and hidden fields (D-016)" do
    defp access_definition do
      declaration = %{
        kind: :object,
        properties: [
          {"serial_number", %{kind: :string, read_only: true}},
          {"location", %{kind: :string}},
          {"legacy_id", %{kind: :string, hidden: true}}
        ]
      }

      {:ok, definition, []} = Formentation.compile(declaration, adapter: Formentation.Source.Map)
      definition
    end

    test "an absent key keeps the original value instead of unsetting it" do
      form = Form.new(access_definition(), %{"serial_number" => "PX-2044"})
      form = Form.transition(form, %Params{values: %{"location" => "Hall B"}})

      assert Form.field(form, ["serial_number"]).operation == :keep

      assert Form.candidate(form) ==
               {:ok, %{"serial_number" => "PX-2044", "location" => "Hall B"}}
    end

    test "a submitted value is discarded: the original wins in candidate and display" do
      form = Form.new(access_definition(), %{"serial_number" => "PX-2044"})

      form =
        Form.transition(form, %Params{
          values: %{"serial_number" => "TAMPERED", "location" => "Hall B"}
        })

      state = Form.field(form, ["serial_number"])
      assert state.operation == :keep
      assert state.transport == {:provided, "TAMPERED"}
      assert state.display_value == "PX-2044"
      assert state.issues == []

      assert Form.candidate(form) ==
               {:ok, %{"serial_number" => "PX-2044", "location" => "Hall B"}}
    end

    test "a read-only field absent from original data stays absent from the candidate" do
      form = Form.new(access_definition(), %{})
      form = Form.transition(form, %Params{values: %{"location" => "Hall B"}})

      assert Form.candidate(form) == {:ok, %{"location" => "Hall B"}}
    end

    test "a hidden field decodes exactly like an unflagged one" do
      form = Form.new(access_definition(), %{"legacy_id" => "L-1"})

      form =
        Form.transition(form, %Params{
          values: %{"legacy_id" => "L-2", "location" => "Hall B"}
        })

      assert Form.field(form, ["legacy_id"]).operation == {:set, "L-2"}
      assert Form.candidate(form) == {:ok, %{"legacy_id" => "L-2", "location" => "Hall B"}}
    end

    test "a required read-only field absent from original surfaces a required issue on submit" do
      schema = %{
        "$schema" => "https://json-schema.org/draft/2020-12/schema",
        "type" => "object",
        "properties" => %{"serial_number" => %{"type" => "string"}},
        "required" => ["serial_number"]
      }

      # diagnostics are non-empty here (:required_permits_empty advisory) — expected
      {:ok, definition, _diagnostics} =
        Formentation.compile(schema,
          adapter: Formentation.JSONSchema,
          ui: %{"fields" => %{"serial_number" => %{"read_only" => true}}}
        )

      form = Form.new(definition, %{})
      form = Form.transition(form, %Params{values: %{}, event: :submit})

      assert [%Issue{code: :required, source: :validation}] = Form.issues(form, ["serial_number"])
      assert Form.show_issues?(form, ["serial_number"])
    end

    test "a read-only field never produces a decode issue, even for undecodable input" do
      declaration = %{
        kind: :object,
        properties: [
          {"revision", %{kind: :integer, read_only: true}},
          {"location", %{kind: :string}}
        ]
      }

      {:ok, definition, []} = Formentation.compile(declaration, adapter: Formentation.Source.Map)
      form = Form.new(definition, %{"revision" => 4})

      form =
        Form.transition(form, %Params{
          values: %{"revision" => "not-a-number", "location" => "Hall B"}
        })

      state = Form.field(form, ["revision"])
      assert state.operation == :keep
      assert state.issues == []
      assert Form.candidate(form) == {:ok, %{"revision" => 4, "location" => "Hall B"}}
    end
  end
end
