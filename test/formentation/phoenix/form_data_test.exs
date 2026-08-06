defmodule Formentation.Phoenix.FormDataTest do
  use ExUnit.Case, async: true

  import Formentation.Test.FormHelpers

  alias Formentation.Fixtures.PumpInspection
  alias Formentation.{Form, Params}
  alias Formentation.Phoenix.ProjectedForm
  alias Phoenix.HTML.FormData

  defp pump_definition do
    {:ok, definition, []} =
      Formentation.compile(PumpInspection.map_source(), adapter: Formentation.Source.Map)

    definition
  end

  defp pump_form(data \\ %{}), do: Form.new(pump_definition(), data)

  defp compile!(declaration) do
    {:ok, definition, _diagnostics} =
      Formentation.compile(declaration, adapter: Formentation.Source.Map)

    definition
  end

  defp nested_definition do
    declaration = %{
      kind: :object,
      required: ["title"],
      properties: [
        {"title", %{kind: :string, min_length: 1}},
        {"address",
         %{
           kind: :object,
           properties: [
             {"street", %{kind: :string}},
             {"number", %{kind: :integer}},
             {"geo", %{kind: :object, properties: [{"lat", %{kind: :number}}]}}
           ]
         }}
      ]
    }

    {:ok, definition, []} = Formentation.compile(declaration, adapter: Formentation.Source.Map)
    definition
  end

  describe "to_form/2" do
    test "projects state into a Phoenix.HTML.Form" do
      data = %{"serial_number" => "PX-2044"}
      form = FormData.to_form(pump_form(data), [])

      assert %Phoenix.HTML.Form{} = form
      assert form.name == nil
      assert form.id == nil
      assert form.data == data
      assert form.params == %{}
      assert form.errors == []
      assert form.action == nil
      assert form.hidden == []
      assert form.index == nil
      assert %Formentation.Form{} = form.source
      assert form.options[:__formentation__] == []
    end

    test ":as sets name and id; :id overrides the id" do
      form = FormData.to_form(pump_form(), as: "payload")
      assert form.name == "payload"
      assert form.id == "payload"

      form = FormData.to_form(pump_form(), as: "payload", id: "custom")
      assert form.id == "custom"
    end

    test "field access produces Phoenix names, bare and under a parent namespace" do
      bare = FormData.to_form(pump_form(), [])
      assert bare[:serial_number].name == "serial_number"
      assert bare[:serial_number].id == "serial_number"

      namespaced = FormData.to_form(pump_form(), as: "asset[payload]")
      assert namespaced[:serial_number].name == "asset[payload][serial_number]"
    end

    test "nesting an anonymous form uses the bare key as id and name" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"address", %{kind: :object, properties: [{"street", %{kind: :string}}]}}
          ]
        })

      state = Form.new(definition, %{"address" => %{"street" => "Elm"}})
      root = Phoenix.HTML.FormData.to_form(state, [])

      assert root.id == nil
      assert root.name == nil

      [address] = Phoenix.HTML.FormData.to_form(state, root, :address, [])

      assert address.id == "address"
      assert address.name == "address"
      assert address[:street].name == "address[street]"
    end

    test "params expose the Phoenix-compatible view after a transition" do
      form_state =
        Form.transition(pump_form(), %Params{
          values: %{
            "serial_number" => "PX-1",
            "_unused_serial_number" => "",
            "condition" => "good",
            "_csrf_token" => "tok"
          },
          event: :change
        })

      form = FormData.to_form(form_state, [])
      assert form.params["_unused_serial_number"] == ""
      assert form.params["_csrf_token"] == "tok"
      assert form.action == :change
    end

    test "rejects options owned by Form state" do
      assert_raise ArgumentError, ~r/owned by Formentation\.Form state/, fn ->
        FormData.to_form(pump_form(), action: :validate)
      end

      assert_raise ArgumentError, ~r/owned by Formentation\.Form state/, fn ->
        FormData.to_form(pump_form(), errors: [name: {"boom", []}])
      end
    end

    test "remaining options are stored" do
      form = FormData.to_form(pump_form(), foo: :bar)
      assert form.options[:foo] == :bar
    end
  end

  describe "native projection metadata" do
    test "decodes root and nested object paths from native forms" do
      form_state = Form.new(nested_definition())
      root = FormData.to_form(form_state, as: "payload", marker: :kept)
      [address] = FormData.to_form(form_state, root, :address, marker: :address)
      [geo] = FormData.to_form(form_state, address, :geo, marker: :geo)

      assert {:ok, %{definition: definition, state: ^form_state, root_path: root_path}} =
               ProjectedForm.native_context(root)

      assert definition == form_state.definition
      assert root_path.segments == []

      assert {:ok, %{state: ^form_state, root_path: %{segments: ["address"]}}} =
               ProjectedForm.native_context(address)

      assert {:ok, %{state: ^form_state, root_path: %{segments: ["address", "geo"]}}} =
               ProjectedForm.native_context(geo)

      assert root.options[:marker] == :kept
      assert address.options[:marker] == :address
      assert geo.options[:marker] == :geo
    end

    test "identifies arbitrary FormData as non-native" do
      form = FormData.to_form(%{}, as: "payload")

      assert :not_native = ProjectedForm.native_context(form)
    end

    test "rejects native forms with missing or invalid projection metadata" do
      form = FormData.to_form(Form.new(nested_definition()), as: "payload")

      assert {:error, :missing_root_path} =
               ProjectedForm.native_context(%{
                 form
                 | options: Keyword.delete(form.options, :__formentation__)
               })

      for invalid_path <- ["address", [:address], ["address", -1]] do
        assert {:error, {:invalid_root_path, ^invalid_path}} =
                 ProjectedForm.native_context(%{form | options: [__formentation__: invalid_path]})
      end
    end

    test "raises actionable guidance when FormData needs malformed native metadata" do
      form = FormData.to_form(Form.new(nested_definition()), as: "payload")
      broken = %{form | options: Keyword.delete(form.options, :__formentation__)}

      assert_raise ArgumentError, ~r/rebuild it through .*to_form.*inputs_for/, fn ->
        ProjectedForm.root_segments!(broken)
      end
    end
  end

  describe "input_value/3" do
    test "returns raw attempted text when decoding failed" do
      form_state =
        Form.transition(pump_form(%{"operating_hours" => 5102}), %Params{
          values: %{"operating_hours" => "51o2"},
          event: :change
        })

      form = FormData.to_form(form_state, [])
      assert form[:operating_hours].value == "51o2"
    end

    test "returns original data encoded for display before interaction" do
      form =
        FormData.to_form(pump_form(%{"operating_hours" => 5102, "insulation_ok" => true}), [])

      assert form[:operating_hours].value == "5102"
      assert form[:insulation_ok].value == "true"
    end

    test "read-only fields display original data, not submitted values (D-016)" do
      {:ok, definition, []} =
        Formentation.compile(Formentation.Fixtures.FieldAccess.map_source(),
          adapter: Formentation.Source.Map
        )

      form_state =
        Form.transition(Form.new(definition, %{"serial_number" => "GENUINE"}), %Params{
          values: %{"serial_number" => "TAMPERED", "location" => "Hall B"},
          event: :change
        })

      form = FormData.to_form(form_state, [])
      assert form[:serial_number].value == "GENUINE"
      assert form[:location].value == "Hall B"
    end

    test "atom and string access agree" do
      form = FormData.to_form(pump_form(%{"notes" => "fine"}), [])
      assert form[:notes].value == form["notes"].value
    end

    test "non-field paths fall back to params-then-data" do
      data = %{"address" => %{"street" => "Main"}}
      form = FormData.to_form(Form.new(nested_definition(), data), [])

      assert form[:address].value == %{"street" => "Main"}
      assert form[:no_such_field].value == nil
    end
  end

  defp json_pump_form(data \\ %{}) do
    {:ok, definition, []} =
      Formentation.compile(PumpInspection.json_schema(),
        adapter: Formentation.JSONSchema,
        ui: PumpInspection.ui_hints()
      )

    Form.new(definition, data)
  end

  describe "errors" do
    test "empty while action is nil, even when issues exist" do
      form_state = json_pump_form()
      refute Enum.empty?(Form.issues(form_state))

      assert FormData.to_form(form_state, []).errors == []
    end

    test "schema issues map to {message, [code:, source:]} tuples keyed for atom access" do
      form_state = Form.transition(json_pump_form(), %Params{values: %{}, event: :submit})
      form = FormData.to_form(form_state, [])

      assert [{message, opts}] = form[:serial_number].errors
      assert is_binary(message)
      assert opts[:code] == :required
      assert opts[:source] == :validation
    end

    test "decode issues surface at :change with deterministic ordering" do
      form_state =
        Form.transition(pump_form(), %Params{
          values: %{"voltage" => "high", "operating_hours" => "many"},
          event: :change
        })

      form = FormData.to_form(form_state, [])

      assert [{:operating_hours, {_, hours_opts}}, {:voltage, {_, volt_opts}}] = form.errors
      assert hours_opts[:code] == :invalid_integer
      assert hours_opts[:source] == :decode
      assert volt_opts[:code] == :invalid_number
    end

    test "issues on fields without an existing atom key fall back to string keys" do
      name = "zzq_" <> "unatomized"

      {:ok, definition, []} =
        Formentation.compile(
          %{kind: :object, properties: [{name, %{kind: :integer}}]},
          adapter: Formentation.Source.Map
        )

      form_state =
        Form.transition(Form.new(definition), %Params{
          values: %{name => "nope"},
          event: :change
        })

      form = FormData.to_form(form_state, [])

      assert [{^name, {_message, _opts}}] = form.errors
      assert [_] = form[name].errors
    end

    test "the root form carries only its direct children's issues" do
      form_state =
        Form.transition(Form.new(nested_definition(), %{"title" => "t"}), %Params{
          values: %{"title" => "t", "address" => %{"number" => "x"}},
          event: :change
        })

      assert FormData.to_form(form_state, []).errors == []
    end

    test "a missing required nested object stays out of the parent's errors" do
      # `address` is a plain supported `"type": "object"`. Under D-026
      # (issue #1) a required nested object with no content is genuinely
      # absent from the candidate rather than materialized as `%{}`, so
      # JSV files the `:required` issue at the group's own path,
      # ["address"] — which must not leak into the parent's scalar errors.
      schema = %{
        "type" => "object",
        "required" => ["address"],
        "properties" => %{
          "title" => %{"type" => "string"},
          "address" => %{
            "type" => "object",
            "required" => ["street"],
            # minLength 1 keeps the compile diagnostic-free: without it the
            # compiler warns :required_permits_empty, and this test asserts
            # a clean compile to prove no *unsupported* keyword is involved.
            "properties" => %{"street" => %{"type" => "string", "minLength" => 1}}
          }
        }
      }

      {:ok, definition, []} = Formentation.compile(schema, adapter: Formentation.JSONSchema)

      form_state = submitted_form(Form.new(definition), %{"title" => "t"})
      form = FormData.to_form(form_state, [])

      assert form.errors == []
      assert [%Formentation.Issue{code: :required}] = Form.issues(form_state, ["address"])
    end
  end

  describe "to_form/4 (nested objects)" do
    defp nested_form(data \\ %{}, values \\ nil, opts \\ []) do
      form_state = Form.new(nested_definition(), data)

      form_state =
        if values,
          do: Form.transition(form_state, %Params{values: values, event: :change}),
          else: form_state

      root = FormData.to_form(form_state, opts)
      {form_state, root, hd(FormData.to_form(form_state, root, :address, []))}
    end

    test "projects a one-element list with scoped naming, params, and data" do
      values = %{"title" => "t", "address" => %{"street" => "Main", "_unused_street" => ""}}
      {_state, root, nested} = nested_form(%{"address" => %{"number" => 7}}, values)

      assert [%Phoenix.HTML.Form{}] = FormData.to_form(root.source, root, :address, [])
      assert nested.name == "address"
      assert nested.id == "address"
      assert nested.params == %{"street" => "Main", "_unused_street" => ""}
      assert nested.data == %{"number" => 7}
      assert nested.action == :change
      assert nested.index == nil
      assert %Formentation.Form{} = nested.source
      assert nested.options[:__formentation__] == ["address"]
    end

    test "namespaced parents prefix nested names and ids" do
      {_state, _root, nested} = nested_form(%{}, nil, as: "payload")

      assert nested.name == "payload[address]"
      assert nested.id == "payload_address"
      assert nested[:street].name == "payload[address][street]"
    end

    test "two nesting levels re-apply the same projection" do
      {form_state, _root, nested} = nested_form()
      geo = hd(FormData.to_form(form_state, nested, :geo, []))

      assert geo.name == "address[geo]"
      assert geo.options[:__formentation__] == ["address", "geo"]
      assert geo[:lat].name == "address[geo][lat]"
    end

    test "nested errors attach to the nested form" do
      values = %{"title" => "t", "address" => %{"number" => "x"}}
      {_state, _root, nested} = nested_form(%{}, values)

      assert [{:number, {_message, opts}}] = nested.errors
      assert opts[:code] == :invalid_integer
      assert nested[:number].errors != []
    end

    test "nested input_value reads through the nested path" do
      # Before any interaction, values come from original data.
      {_state, _root, nested} = nested_form(%{"address" => %{"street" => "Main"}})
      assert nested[:street].value == "Main"

      # After a replace transition, submitted raw values win — and an
      # omitted street would display "" (cleared stays cleared, D-013).
      values = %{"title" => "t", "address" => %{"number" => "x", "street" => "Elm"}}
      {_state, _root, nested} = nested_form(%{}, values)

      assert nested[:number].value == "x"
      assert nested[:street].value == "Elm"
    end

    test "raises for anything that is not a data-nesting object" do
      {form_state, root, _nested} = nested_form()

      for field <- [:title, :no_such_field] do
        assert_raise ArgumentError, ~r/data-nesting objects/, fn ->
          FormData.to_form(form_state, root, field, [])
        end
      end
    end

    test "presentation groups never become nested forms" do
      form_state = pump_form()
      root = FormData.to_form(form_state, [])

      assert_raise ArgumentError, ~r/data-nesting objects/, fn ->
        FormData.to_form(form_state, root, :electrical, [])
      end
    end

    test "rejects collection-era and state-owned options" do
      {form_state, root, _nested} = nested_form()

      for {key, value} <- [default: %{}, prepend: [%{}], append: [%{}]] do
        assert_raise ArgumentError, ~r/Milestone B/, fn ->
          FormData.to_form(form_state, root, :address, [{key, value}])
        end
      end

      assert_raise ArgumentError, ~r/owned by Formentation\.Form state/, fn ->
        FormData.to_form(form_state, root, :address, action: :validate)
      end

      assert_raise ArgumentError, ~r/owned by Formentation\.Form state/, fn ->
        FormData.to_form(form_state, root, :address, errors: [street: {"boom", []}])
      end

      # nil values for the collection options are tolerated (components may
      # pass explicit nils); they are simply dropped
      assert [_form] = FormData.to_form(form_state, root, :address, default: nil)
    end
  end

  describe "input_validations/3" do
    defp validations(form, field), do: Phoenix.HTML.Form.input_validations(form, field)

    test "derives from schema plus input policy, never from required alone" do
      form = FormData.to_form(pump_form(), [])

      # required string with min_length >= 1
      assert validations(form, :serial_number) == [required: true, minlength: 4]
      # required string whose option set excludes ""
      assert validations(form, :condition) == [required: true]
      # optional string: nothing
      assert validations(form, :notes) == []
      # optional integer with a numeric bound
      assert validations(form, :operating_hours) == [min: 0, step: 1]
      # optional number
      assert validations(form, :voltage) == [step: "any"]
      # optional boolean
      assert validations(form, :insulation_ok) == []
    end

    test "a required string permitting empty input gets no required attribute" do
      {:ok, definition, [diagnostic]} =
        Formentation.compile(
          %{kind: :object, required: ["note"], properties: [{"note", %{kind: :string}}]},
          adapter: Formentation.Source.Map
        )

      assert diagnostic.code == :required_permits_empty

      form = FormData.to_form(Form.new(definition), [])
      assert validations(form, :note) == []
    end

    test "a required typed field gets the required attribute" do
      {:ok, definition, []} =
        Formentation.compile(
          %{kind: :object, required: ["count"], properties: [{"count", %{kind: :integer}}]},
          adapter: Formentation.Source.Map
        )

      form = FormData.to_form(Form.new(definition), [])
      assert validations(form, :count) == [required: true, step: 1]
    end

    test "non-field paths yield no validations" do
      form = FormData.to_form(Form.new(nested_definition()), [])
      assert validations(form, :address) == []
      assert validations(form, :no_such_field) == []
    end

    test "nested validations resolve from the shared projection path" do
      {_state, _root, nested} = nested_form()

      assert validations(nested, :number) == [step: 1]
    end

    test "maximum constraints map to their HTML counterparts" do
      {:ok, definition, []} =
        Formentation.compile(
          %{
            kind: :object,
            properties: [
              {"code", %{kind: :string, max_length: 12}},
              {"quantity", %{kind: :integer, max: 99}}
            ]
          },
          adapter: Formentation.Source.Map
        )

      form = FormData.to_form(Form.new(definition), [])
      assert validations(form, :code) == [maxlength: 12]
      assert validations(form, :quantity) == [max: 99, step: 1]
    end
  end
end
