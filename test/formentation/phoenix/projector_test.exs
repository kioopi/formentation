defmodule Formentation.Phoenix.ProjectorTest do
  use ExUnit.Case, async: true

  doctest Formentation.Phoenix.Projector

  alias Formentation.Form
  alias Formentation.Phoenix.{Projector, RenderNode, RenderPlan}
  alias Phoenix.HTML.FormData

  defp compile!(declaration) do
    {:ok, definition, _diagnostics} =
      Formentation.compile(declaration, adapter: Formentation.Source.Map)

    definition
  end

  defp flat_definition do
    compile!(%{
      kind: :object,
      required: ["serial_number"],
      properties: [
        {"serial_number", %{kind: :string, title: "Serial number", min_length: 4}},
        {"operating_hours", %{kind: :integer, title: "Operating hours"}},
        {"notes", %{kind: :string, help: "Visible to all technicians."}}
      ]
    })
  end

  defp decode_error_form(event, extra_values \\ %{}) do
    definition = flat_definition()

    values =
      Map.merge(
        %{"serial_number" => "PX-2044", "operating_hours" => "51o2", "notes" => ""},
        extra_values
      )

    form_state =
      Form.transition(Form.new(definition), %Formentation.Params{values: values, event: event})

    {definition, FormData.to_form(form_state, [])}
  end

  describe "project/2 with flat scalar fields" do
    test "emits one component-ready render node per field, in order" do
      definition = flat_definition()

      form =
        FormData.to_form(Form.new(definition, %{"serial_number" => "PX-2044"}), as: "payload")

      plan = Projector.project(definition, form)

      assert %RenderPlan{root: %RenderNode.Group{} = root, summary: [], diagnostics: []} = plan

      assert [%RenderNode.Field{} = serial, %RenderNode.Field{}, %RenderNode.Field{} = notes] =
               root.children

      assert serial.label == "Serial number"
      assert serial.field.name == "payload[serial_number]"
      assert serial.field.value == "PX-2044"
      assert serial.validations == [required: true, minlength: 4]
      assert serial.errors == []
      refute serial.show_errors?
      refute serial.read_only?

      assert notes.help == "Visible to all technicians."
    end

    test "label falls back to the humanized field name" do
      definition = compile!(%{kind: :object, properties: [{"serial_number", %{kind: :string}}]})
      form = FormData.to_form(Form.new(definition), [])

      plan = Projector.project(definition, form)

      assert [%RenderNode.Field{label: "Serial number"}] = plan.root.children
    end

    test "errors attach through the existing-atom access convention" do
      # Map-source forms have no schema validator (recorded in the open
      # questions), so the only issue source is a DECODE failure — an
      # integer field receiving "51o2". :operating_hours exists as an
      # atom (this file mentions it), so FormData keys its error by atom;
      # the projector must access the field the same way or the error
      # never reaches the render node.
      definition = flat_definition()

      form_state =
        Form.transition(Form.new(definition), %Formentation.Params{
          values: %{"serial_number" => "PX-2044", "operating_hours" => "51o2", "notes" => ""},
          event: :submit
        })

      form = FormData.to_form(form_state, [])
      plan = Projector.project(definition, form)

      [_serial, hours, _notes] = plan.root.children
      assert hours.field.field == :operating_hours
      assert hours.field.value == "51o2"
      assert [{message, opts}] = hours.errors
      assert is_binary(message)
      assert opts[:code] == :invalid_integer
    end
  end

  defp single_field_plan(spec) do
    definition = compile!(%{kind: :object, properties: [{"f", spec}]})
    form = FormData.to_form(Form.new(definition), [])
    Projector.project(definition, form)
  end

  defp single_widget(spec) do
    plan = single_field_plan(spec)
    [%RenderNode.Field{widget: widget}] = plan.root.children
    {widget, plan.diagnostics}
  end

  describe "widget resolution" do
    test "infers from options, value type, and role" do
      assert {:text_input, []} = single_widget(%{kind: :string})
      assert {:select, []} = single_widget(%{kind: :string, one_of: ["a", "b"]})
      assert {:checkbox, []} = single_widget(%{kind: :boolean})
      assert {:number_input, []} = single_widget(%{kind: :integer})
      assert {:number_input, []} = single_widget(%{kind: :number})
      assert {:date_input, []} = single_widget(%{kind: :string, role: :date})
      assert {:email_input, []} = single_widget(%{kind: :string, role: :email})
      assert {:url_input, []} = single_widget(%{kind: :string, role: :uri})
    end

    test "a sensible hint wins over inference" do
      assert {:textarea, []} = single_widget(%{kind: :string, widget: :textarea})
      assert {:text_input, []} = single_widget(%{kind: :string, one_of: ["a"], widget: :text})
      assert {:radio_group, []} = single_widget(%{kind: :string, one_of: ["a"], widget: :radio})
      assert {:select, []} = single_widget(%{kind: :string, one_of: ["a"], widget: :select})
      assert {:checkbox, []} = single_widget(%{kind: :boolean, widget: :checkbox})
    end

    test "a hidden field is a hidden input regardless of hints" do
      assert {:hidden_input, []} =
               single_widget(%{kind: :string, widget: :textarea, hidden: true})
    end

    test "nonsense hints fall back to the inferred widget with a diagnostic" do
      # :checkbox on a non-boolean (D-011 is boolean-shaped), optionless
      # :select/:radio, and unknown atoms from the unvalidated map source.
      for {spec, expected} <- [
            {%{kind: :string, widget: :checkbox}, :text_input},
            {%{kind: :string, widget: :select}, :text_input},
            {%{kind: :integer, widget: :radio}, :number_input},
            {%{kind: :string, widget: :fancy_slider}, :text_input}
          ] do
        {widget, diagnostics} = single_widget(spec)
        assert widget == expected

        assert [%Formentation.Diagnostic{severity: :warning, code: :widget_fallback}] =
                 diagnostics
      end
    end
  end

  describe "groups and non-rendering nodes" do
    test "a presentational group nests render nodes without name nesting" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"serial_number", %{kind: :string}},
            {"voltage", %{kind: :number}},
            {"insulation_ok", %{kind: :boolean}}
          ],
          groups: [%{id: "electrical", title: "Electrical", fields: ["voltage", "insulation_ok"]}]
        })

      form = FormData.to_form(Form.new(definition), as: "payload")
      plan = Projector.project(definition, form)

      assert [%RenderNode.Field{}, %RenderNode.Group{legend: "Electrical"} = group] =
               plan.root.children

      assert [%RenderNode.Field{} = voltage, %RenderNode.Field{}] = group.children
      assert voltage.field.name == "payload[voltage]"
    end

    test "a data-nesting group projects children under the nested form" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"title", %{kind: :string}},
            {"address",
             %{kind: :object, title: "Address", properties: [{"street", %{kind: :string}}]}}
          ]
        })

      form =
        FormData.to_form(Form.new(definition, %{"address" => %{"street" => "Elm"}}),
          as: "payload"
        )

      plan = Projector.project(definition, form)

      assert [_title, %RenderNode.Group{legend: "Address"} = address] = plan.root.children
      assert [%RenderNode.Field{} = street] = address.children
      assert street.field.name == "payload[address][street]"
      assert street.field.value == "Elm"
    end

    test "unsupported nodes and hidden read-only fields render nothing" do
      # %{kind: :carousel} compiles to Node.Unsupported with an
      # :unsupported_kind warning (see map_test.exs) — the projector
      # must skip it without schema text leaking into markup.
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"gadget", %{kind: :carousel}},
            {"secret", %{kind: :string, hidden: true, read_only: true}},
            {"name", %{kind: :string}}
          ]
        })

      form = FormData.to_form(Form.new(definition), [])
      plan = Projector.project(definition, form)

      assert [%RenderNode.Field{label: "Name"}] = plan.root.children
    end
  end

  describe "project_at/3" do
    defp subtree_definition do
      compile!(%{
        kind: :object,
        properties: [
          {"gadget", %{kind: :carousel}},
          {"secret", %{kind: :string, hidden: true, read_only: true}},
          {"address",
           %{kind: :object, title: "Address", properties: [{"street", %{kind: :string}}]}}
        ]
      })
    end

    test "a data-nesting group path returns a Group whose children carry the nested names" do
      definition = subtree_definition()

      form =
        FormData.to_form(Form.new(definition, %{"address" => %{"street" => "Elm"}}),
          as: "payload"
        )

      assert %RenderNode.Group{legend: "Address", children: [street]} =
               Projector.project_at(definition, form, ["address"])

      assert %RenderNode.Field{} = street
      assert street.field.name == "payload[address][street]"
      assert street.field.value == "Elm"
    end

    test "an unsupported node's path raises" do
      definition = subtree_definition()
      form = FormData.to_form(Form.new(definition), [])

      assert_raise ArgumentError, ~r/unsupported/, fn ->
        Projector.project_at(definition, form, ["gadget"])
      end
    end

    test "a hidden read-only field's path renders nothing" do
      definition = subtree_definition()
      form = FormData.to_form(Form.new(definition), [])

      assert Projector.project_at(definition, form, ["secret"]) == nil
    end
  end

  describe "error visibility and the summary" do
    test "on submit every field error is visible and summarized" do
      {definition, form} = decode_error_form(:submit)
      plan = Projector.project(definition, form)

      [_serial, hours, _notes] = plan.root.children
      assert hours.show_errors?
      assert [%{id: id, label: "Operating hours", message: message}] = plan.summary
      assert id == hours.field.id
      assert is_binary(message)
    end

    test "on change an unused field stores its error invisibly" do
      {definition, form} = decode_error_form(:change, %{"_unused_operating_hours" => ""})
      plan = Projector.project(definition, form)

      [_serial, hours, _notes] = plan.root.children
      assert hours.errors != []
      refute hours.show_errors?
      assert plan.summary == []
    end

    test "on change a used field shows its error but the summary stays empty" do
      {definition, form} = decode_error_form(:change)
      plan = Projector.project(definition, form)

      [_serial, hours, _notes] = plan.root.children
      assert hours.show_errors?
      assert plan.summary == []
    end

    test "projection is pure and mutates nothing" do
      {definition, form} = decode_error_form(:submit)
      source_before = form.source

      plan1 = Projector.project(definition, form)
      plan2 = Projector.project(definition, form)

      assert plan1 == plan2
      assert form.source == source_before
    end

    test "object-level schema issues enrich the submit summary unlinked" do
      # `address` is deliberately modeled with `oneOf` (unsupported by the
      # JSON Schema adapter) rather than a plain `"type": "object"`: a
      # supported nested object's children are always materialized present,
      # so a `required` issue can never land on the group's own path. An
      # Unsupported node is the one shape that can genuinely be missing —
      # JSV files the `:required` issue at ["address"], and since that path
      # doesn't resolve to a Node.Field, object_entries/1 folds it into the
      # summary unlinked (no id, no label). Mirrors
      # form_data_test.exs:234-269.
      schema = %{
        "type" => "object",
        "required" => ["address"],
        "properties" => %{
          "title" => %{"type" => "string"},
          "address" => %{
            "oneOf" => [
              %{"type" => "object", "properties" => %{"street" => %{"type" => "string"}}}
            ]
          }
        }
      }

      {:ok, definition, [diagnostic]} =
        Formentation.compile(schema, adapter: Formentation.JSONSchema)

      assert diagnostic.code == :unsupported_keyword

      form_state =
        Form.transition(Form.new(definition), %Formentation.Params{
          values: %{"title" => "t"},
          event: :submit
        })

      form = FormData.to_form(form_state, [])
      plan = Projector.project(definition, form)

      assert [%{id: nil, label: nil, message: message}] = plan.summary
      assert message =~ "required"
    end
  end
end
