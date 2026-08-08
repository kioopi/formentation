defmodule Formentation.Phoenix.ComponentsTest do
  use ExUnit.Case, async: true

  doctest Formentation.Phoenix

  import Formentation.HTMLAssertions
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Formentation.{Form, InstancePath}
  alias Formentation.Form.Params
  alias Formentation.Phoenix.{DOMIdentity, StateView}
  alias Phoenix.HTML.FormData

  defp compile!(declaration) do
    {:ok, definition, _diagnostics} =
      Formentation.compile(declaration, adapter: Formentation.Source.Map)

    definition
  end

  defp compile_json!(schema) do
    {:ok, definition, _diagnostics} =
      Formentation.compile(schema, adapter: Formentation.Source.JSONSchema)

    definition
  end

  defp nested_definition do
    compile!(%{
      kind: :object,
      required: ["serial_number"],
      properties: [
        {"serial_number", %{kind: :string, title: "Serial number", min_length: 4}},
        {"operating_hours", %{kind: :integer, title: "Operating hours"}},
        {"address",
         %{kind: :object, title: "Address", properties: [{"street", %{kind: :string}}]}}
      ]
    })
  end

  defp render_fields(definition, form) do
    render_component(&Formentation.Phoenix.fields/1, definition: definition, form: form)
  end

  defp field_id(namespace, path, part),
    do: DOMIdentity.field(namespace, InstancePath.new!(path), part)

  defp assert_all_references_resolve(doc) do
    ids = doc |> Floki.find("[id]") |> Enum.flat_map(&Floki.attribute(&1, "id")) |> MapSet.new()

    label_targets = doc |> Floki.find("label[for]") |> Enum.flat_map(&Floki.attribute(&1, "for"))

    describedby_targets =
      doc
      |> Floki.find("[aria-describedby]")
      |> Enum.flat_map(&Floki.attribute(&1, "aria-describedby"))
      |> Enum.flat_map(&String.split(&1, " ", trim: true))

    summary_targets =
      doc
      |> Floki.find("a[href^='#']")
      |> Enum.flat_map(&Floki.attribute(&1, "href"))
      |> Enum.map(&String.replace_prefix(&1, "#", ""))

    dangling =
      MapSet.difference(MapSet.new(label_targets ++ describedby_targets ++ summary_targets), ids)

    assert MapSet.to_list(dangling) == []
  end

  describe "fields/1" do
    test "numeric fields hinted to non-numeric widgets omit numeric constraint attributes" do
      fields = [
        {"count", %{kind: :integer, min: 0, max: 100, widget: :text}, "input"},
        {"hours", %{kind: :integer, min: 0, max: 100, widget: :textarea}, "textarea"},
        {"rating", %{kind: :integer, min: 0, max: 100, one_of: [1, 2]}, "select"}
      ]

      definition =
        compile!(%{
          kind: :object,
          required: Enum.map(fields, &elem(&1, 0)),
          properties: Enum.map(fields, fn {name, field, _selector} -> {name, field} end)
        })

      doc =
        parse!(render_fields(definition, FormData.to_form(Form.new(definition), as: "payload")))

      for {name, _field, selector} <- fields do
        control = find_one(doc, ~s(#{selector}[id="#{field_id("payload", [name], :control)}"]))

        assert Floki.attribute(control, "required") == ["required"]
        assert Floki.attribute(control, "min") == []
        assert Floki.attribute(control, "max") == []
        assert Floki.attribute(control, "step") == []
      end
    end

    test "renders numeric select and radio options as selected after projection" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"count", %{kind: :integer, one_of: [1, 2]}},
            {"rating", %{kind: :integer, one_of: [1, 2], widget: :radio}}
          ]
        })

      form = FormData.to_form(Form.new(definition, %{"count" => 2, "rating" => 2}), as: "payload")
      doc = parse!(render_fields(definition, form))

      [selected] =
        Floki.find(
          doc,
          ~s(select[id="#{field_id("payload", ["count"], :control)}"] option[selected])
        )

      assert Floki.attribute(selected, "value") == ["2"]

      [checked] =
        Floki.find(
          doc,
          ~s(fieldset[id="#{field_id("payload", ["rating"], :container)}"] input[checked])
        )

      assert Floki.attribute(checked, "value") == ["2"]
    end

    test "retains numeric option selections after a failed sibling decode" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"count", %{kind: :integer, one_of: [1, 2]}},
            {"rating", %{kind: :integer, one_of: [1, 2], widget: :radio}},
            {"fault", %{kind: :integer}}
          ]
        })

      form_state =
        Form.transition(Form.new(definition), %Params{
          values: %{"count" => "2", "rating" => "2", "fault" => "broken"},
          event: :change
        })

      doc = parse!(render_fields(definition, FormData.to_form(form_state, as: "payload")))

      [selected] =
        Floki.find(
          doc,
          ~s(select[id="#{field_id("payload", ["count"], :control)}"] option[selected])
        )

      [checked] =
        Floki.find(
          doc,
          ~s(fieldset[id="#{field_id("payload", ["rating"], :container)}"] input[checked])
        )

      assert Floki.attribute(selected, "value") == ["2"]
      assert Floki.attribute(checked, "value") == ["2"]
    end

    test "renders integer and number fields with their distinct keyboard hints" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"count", %{kind: :integer}},
            {"ratio", %{kind: :number}}
          ]
        })

      doc =
        parse!(render_fields(definition, FormData.to_form(Form.new(definition), as: "payload")))

      for {name, inputmode} <- [{"count", "numeric"}, {"ratio", "decimal"}] do
        control = find_one(doc, ~s(input[id="#{field_id("payload", [name], :control)}"]))
        assert Floki.attribute(control, "name") == ["payload[#{name}]"]
        assert Floki.attribute(control, "type") == ["text"]
        assert Floki.attribute(control, "inputmode") == [inputmode]
      end

      assert Floki.find(doc, "input[type=number]") == []
    end

    test "an invalid radio summary links to the rendered radio container" do
      definition =
        compile!(%{
          kind: :object,
          properties: [{"condition", %{kind: :string, one_of: ["yes", "no"], widget: :radio}}]
        })

      source = %Formentation.SourceFixture{
        params: %{"condition" => ""},
        errors: [condition: {"is required", []}],
        submitted?: true,
        visibility: %{
          ["condition"] => :show
        }
      }

      doc = parse!(render_fields(definition, FormData.to_form(source, as: "payload")))
      target = DOMIdentity.field("payload", InstancePath.new!(["condition"]), :container)

      find_one(doc, ~s(a[href="##{target}"]))
      find_one(doc, ~s(fieldset[id="#{target}"]))
      assert_all_references_resolve(doc)
    end

    # #34: the summary link and the focus target are two different
    # concerns proved together — the href must resolve to exactly one
    # fieldset, and that fieldset must be a valid, non-tab-stop focus
    # target for the anchor to actually move focus somewhere meaningful.
    test "an object-level issue links to a focusable fieldset" do
      definition = nested_definition()

      source = %Formentation.SourceFixture{
        params: %{"serial_number" => "PX-01", "address" => %{"street" => "Elm"}},
        submitted?: true,
        issues:
          {:ok,
           [%StateView.Issue{path: InstancePath.new!(["address"]), message: "is incomplete"}]}
      }

      doc = parse!(render_fields(definition, FormData.to_form(source, as: "payload")))
      target = DOMIdentity.object("payload", InstancePath.new!(["address"]), :container)

      link = find_one(doc, ~s(a[href="##{target}"]))
      assert Floki.text(link) =~ "Address"
      assert Floki.text(link) =~ "is incomplete"

      fieldset = find_one(doc, ~s(fieldset[id="#{target}"]))
      assert Floki.attribute(fieldset, "tabindex") == ["-1"]

      assert_all_references_resolve(doc)
      assert_no_duplicate_ids(doc)
    end

    # A presentation-only group is never a summary target (#34), so it must
    # not carry the same focus-target contract an `:object` fieldset does.
    test "a presentation group's fieldset carries no tabindex" do
      definition =
        compile!(%{
          kind: :object,
          properties: [{"a", %{kind: :string}}, {"b", %{kind: :string}}],
          groups: [%{id: "late", title: "Late", fields: ["a", "b"]}]
        })

      doc =
        definition
        |> Form.new()
        |> FormData.to_form(as: "payload", id: "payload")
        |> then(&render_fields(definition, &1))
        |> parse!()

      group_target =
        DOMIdentity.group("payload", "/#late", InstancePath.new!([]), :container)

      fieldset = find_one(doc, ~s(fieldset[id="#{group_target}"]))
      assert Floki.attribute(fieldset, "tabindex") == []
    end

    test "a hidden field error does not produce an unusable summary link" do
      definition =
        compile!(%{kind: :object, properties: [{"token", %{kind: :string, hidden: true}}]})

      source = %Formentation.SourceFixture{
        params: %{"token" => ""},
        errors: [token: {"is invalid", []}],
        submitted?: true,
        visibility: %{["token"] => :show}
      }

      doc = parse!(render_fields(definition, FormData.to_form(source, as: "payload")))

      assert Floki.find(doc, ".ftn-error-summary") == []
      assert_all_references_resolve(doc)
    end

    test "every reference-UI widget with an error has one resolvable summary target" do
      widgets = [
        {"text", :text, %{kind: :string}, :control},
        {"textarea", :textarea, %{kind: :string, widget: :textarea}, :control},
        {"select", :select, %{kind: :string, one_of: ["one", "two"]}, :control},
        {"radio", :radio, %{kind: :string, one_of: ["one", "two"], widget: :radio}, :container},
        {"checkbox", :checkbox, %{kind: :boolean}, :control},
        {"number", :number, %{kind: :integer}, :control},
        {"date", :date, %{kind: :string, role: :date}, :control},
        {"email", :email, %{kind: :string, role: :email}, :control},
        {"url", :url, %{kind: :string, role: :uri}, :control}
      ]

      definition =
        compile!(%{
          kind: :object,
          properties: Enum.map(widgets, fn {name, _key, field, _part} -> {name, field} end)
        })

      source = %Formentation.SourceFixture{
        params: Map.new(widgets, fn {name, _key, _field, _part} -> {name, ""} end),
        errors:
          Enum.map(widgets, fn {_name, key, _field, _part} -> {key, {"is invalid", []}} end),
        submitted?: true,
        visibility: Map.new(widgets, fn {name, _key, _field, _part} -> {[name], :show} end)
      }

      doc = parse!(render_fields(definition, FormData.to_form(source, as: "payload")))

      for {name, _key, _field, part} <- widgets do
        target = field_id("payload", [name], part)
        assert [_] = Floki.find(doc, ~s(a[href="##{target}"]))
        assert [_] = Floki.find(doc, ~s([id="#{target}"]))
      end

      assert_all_references_resolve(doc)
    end

    test "renders the whole body under a parent namespace without a form element" do
      definition = nested_definition()

      form =
        FormData.to_form(Form.new(definition, %{"address" => %{"street" => "Elm"}}),
          as: "asset[payload]",
          id: "asset_payload"
        )

      html = render_fields(definition, form)
      doc = parse!(html)

      assert Floki.find(doc, "form") == []
      find_one(doc, "div.ftn-form")

      serial =
        find_one(doc, ~s(input[id="#{field_id("asset_payload", ["serial_number"], :control)}"]))

      assert Floki.attribute(serial, "name") == ["asset[payload][serial_number]"]
      assert_labelled(doc, field_id("asset_payload", ["serial_number"], :control))

      street =
        find_one(
          doc,
          ~s(input[id="#{field_id("asset_payload", ["address", "street"], :control)}"])
        )

      assert Floki.attribute(street, "name") == ["asset[payload][address][street]"]
      assert Floki.attribute(street, "value") == ["Elm"]

      assert_no_duplicate_ids(doc)
    end

    test "renders nested group help while omitting root help" do
      definition =
        compile!(%{
          kind: :object,
          help: "Root help.",
          properties: [
            {"notes", %{kind: :string, help: "Field help."}},
            {"address",
             %{
               kind: :object,
               help: "Group help.",
               properties: [{"street", %{kind: :string}}]
             }}
          ]
        })

      form = FormData.to_form(Form.new(definition), as: "payload")
      html = render_fields(definition, form)
      doc = parse!(html)
      notes_control_id = field_id("payload", ["notes"], :control)
      notes_help_id = field_id("payload", ["notes"], :help)
      address_id = DOMIdentity.object("payload", InstancePath.new!(["address"]), :container)
      address_help_id = DOMIdentity.object("payload", InstancePath.new!(["address"]), :help)

      assert Floki.text(find_one(doc, ~s(p[id="#{notes_help_id}"].ftn-help))) |> String.trim() ==
               "Field help."

      assert describedby(doc, notes_control_id) == [notes_help_id]
      assert Floki.text(find_one(doc, ".ftn-group-help")) |> String.trim() == "Group help."
      assert describedby(doc, address_id) == [address_help_id]
      refute html =~ "Root help."
      assert_no_duplicate_ids(doc)
      assert_all_references_resolve(doc)
    end

    test "after submit the error summary links to the broken control" do
      # Map-source forms have no schema validator; the error is a decode
      # failure on the integer field.
      definition = nested_definition()

      form_state =
        Form.transition(Form.new(definition), %Params{
          values: %{
            "serial_number" => "PX-2044",
            "operating_hours" => "51o2",
            "address" => %{"street" => ""}
          },
          event: :submit
        })

      form = FormData.to_form(form_state, as: "payload", id: "payload")
      doc = parse!(render_fields(definition, form))

      find_one(doc, "div.ftn-error-summary[role=alert]")
      target = field_id("payload", ["operating_hours"], :control)
      find_one(doc, ~s(a[href="##{target}"]))
    end

    test "renders reordered groups in presentation order without changing names" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"a", %{kind: :string}},
            {"b", %{kind: :string}},
            {"c", %{kind: :string}},
            {"d", %{kind: :string}}
          ],
          groups: [%{id: "late", title: "Late", fields: ["d", "b"]}]
        })

      doc =
        definition
        |> Form.new()
        |> FormData.to_form(as: "payload", id: "payload")
        |> then(&render_fields(definition, &1))
        |> parse!()

      names =
        doc
        |> Floki.find("input")
        |> Enum.map(fn input -> input |> Floki.attribute("name") |> List.first() end)

      ids =
        doc
        |> Floki.find("input")
        |> Enum.map(fn input -> input |> Floki.attribute("id") |> List.first() end)

      assert names == ["payload[a]", "payload[d]", "payload[b]", "payload[c]"]

      assert ids == Enum.map(["a", "d", "b", "c"], &field_id("payload", [&1], :control))

      refute Enum.any?(names, &String.contains?(&1, "late"))
    end

    test "uses an explicit DOM namespace without changing Phoenix transport names" do
      definition = nested_definition()
      form = FormData.to_form(Form.new(definition), as: "payload")

      doc =
        render_component(&Formentation.Phoenix.fields/1,
          definition: definition,
          form: form,
          dom_namespace: "asset_payload"
        )
        |> parse!()

      input = find_one(doc, ~s([id="#{field_id("asset_payload", ["serial_number"], :control)}"]))
      assert Floki.attribute(input, "name") == ["payload[serial_number]"]
    end

    test "before any action there is no summary and no visible error" do
      definition = nested_definition()
      form = FormData.to_form(Form.new(definition), as: "payload")
      doc = parse!(render_fields(definition, form))

      assert Floki.find(doc, ".ftn-error-summary") == []
      assert Floki.find(doc, ".ftn-errors") == []
    end

    test "raises with namespace guidance when the form has neither name nor id" do
      definition = nested_definition()
      form = FormData.to_form(Form.new(definition), [])

      assert_raise ArgumentError, ~r/Formentation cannot mint DOM ids without a namespace/, fn ->
        render_fields(definition, form)
      end
    end

    test "adversarial names, paths, roles, and group ids remain separately addressable" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"notes", %{kind: :string, help: "Notes help"}},
            {"notes_help", %{kind: :string}},
            {"notes_errors", %{kind: :string}},
            {"a_b", %{kind: :string}},
            {"a", %{kind: :object, properties: [{"b", %{kind: :string}}]}},
            {"condition", %{kind: :string, one_of: ["yes", "no"], widget: :radio}},
            {"condition--option_0", %{kind: :string}},
            {"serial-number", %{kind: :string}},
            {"first name", %{kind: :string}},
            {"0starts_with_a_digit", %{kind: :string}},
            {"left",
             %{
               kind: :object,
               properties: [{"value", %{kind: :string}}],
               groups: [%{id: "details", title: "Details", fields: ["value"]}]
             }},
            {"right",
             %{
               kind: :object,
               properties: [{"value", %{kind: :string}}],
               groups: [%{id: "details", title: "Details", fields: ["value"]}]
             }}
          ],
          groups: [%{id: "notes_help", fields: ["notes", "notes_help"]}]
        })

      doc =
        definition
        |> Form.new()
        |> FormData.to_form(as: "payload")
        |> then(&render_fields(definition, &1))
        |> parse!()

      notes_control = DOMIdentity.field("payload", InstancePath.new!(["notes"]), :control)
      notes_help = DOMIdentity.field("payload", InstancePath.new!(["notes"]), :help)

      notes_help_control =
        DOMIdentity.field("payload", InstancePath.new!(["notes_help"]), :control)

      notes_errors_control =
        DOMIdentity.field("payload", InstancePath.new!(["notes_errors"]), :control)

      flat_path = DOMIdentity.field("payload", InstancePath.new!(["a_b"]), :control)
      nested_path = DOMIdentity.field("payload", InstancePath.new!(["a", "b"]), :control)
      radio_option = DOMIdentity.field("payload", InstancePath.new!(["condition"]), {:option, 0})

      option_like_field =
        DOMIdentity.field("payload", InstancePath.new!(["condition--option_0"]), :control)

      assert_no_duplicate_ids(doc)

      for id <- doc |> Floki.find("[id]") |> Enum.flat_map(&Floki.attribute(&1, "id")) do
        assert [_] = Floki.find(doc, "##{id}")
      end

      assert_labelled(doc, notes_control)
      assert describedby(doc, notes_control) == [notes_help]
      assert_labelled(doc, notes_help_control)
      assert_labelled(doc, notes_errors_control)
      assert_labelled(doc, flat_path)
      assert_labelled(doc, nested_path)
      assert_labelled(doc, radio_option)
      assert_labelled(doc, option_like_field)

      assert_labelled(
        doc,
        DOMIdentity.field("payload", InstancePath.new!(["serial-number"]), :control)
      )

      assert_labelled(
        doc,
        DOMIdentity.field("payload", InstancePath.new!(["first name"]), :control)
      )

      assert_labelled(
        doc,
        DOMIdentity.field("payload", InstancePath.new!(["0starts_with_a_digit"]), :control)
      )

      assert_all_references_resolve(doc)

      assert 2 ==
               doc
               |> Floki.find("fieldset.ftn-group legend")
               |> Enum.count(&(Floki.text(&1) == "Details"))
    end

    test "two occurrences of one definition can coexist under distinct namespaces" do
      definition = nested_definition()
      form = FormData.to_form(Form.new(definition), as: "payload")

      doc =
        (render_fields(definition, form) <>
           render_component(&Formentation.Phoenix.fields/1,
             definition: definition,
             form: form,
             dom_namespace: "comparison_payload"
           ))
        |> parse!()

      assert_no_duplicate_ids(doc)
      assert_all_references_resolve(doc)
    end
  end

  describe "native projected component inputs" do
    test "renders a native root form without a definition assign" do
      definition = nested_definition()
      form = FormData.to_form(Form.new(definition), as: "payload")

      doc =
        render_component(&Formentation.Phoenix.fields/1, form: form)
        |> parse!()

      assert [_] = Floki.find(doc, ~s(input[name="payload[serial_number]"]))
    end

    test "renders only a nested native form and resolves a relative field path" do
      definition = nested_definition()
      form_state = Form.new(definition, %{"address" => %{"street" => "Elm"}})
      root = FormData.to_form(form_state, as: "asset[payload]", id: "asset_payload")
      [address] = FormData.to_form(form_state, root, :address, [])

      nested_doc =
        render_component(&Formentation.Phoenix.fields/1, form: address)
        |> parse!()

      assert [_] = Floki.find(nested_doc, ~s(input[name="asset[payload][address][street]"]))
      assert Floki.find(nested_doc, ~s(input[name="asset[payload][serial_number]"])) == []

      field_doc =
        render_component(&Formentation.Phoenix.field/1, form: address, path: ["street"])
        |> parse!()

      assert [_] = Floki.find(field_doc, ~s(input[name="asset[payload][address][street]"]))
    end

    test "a generic source drives submission, visibility, and non-field issues" do
      definition = nested_definition()

      source = %Formentation.SourceFixture{
        params: %{"serial_number" => "PX", "address" => %{}},
        errors: [serial_number: {"is too short", []}],
        submitted?: true,
        visibility: %{["serial_number"] => :show},
        issues:
          {:ok,
           [
             %Formentation.Phoenix.StateView.Issue{
               path: InstancePath.new!([]),
               message: "fix the form"
             }
           ]}
      }

      form = FormData.to_form(source, as: "payload")

      doc =
        render_component(&Formentation.Phoenix.fields/1, definition: definition, form: form)
        |> parse!()

      assert [_] = Floki.find(doc, ~s(div.ftn-error-summary[role="alert"]))

      serial_control = field_id("payload", ["serial_number"], :control)
      assert [_] = Floki.find(doc, ~s(a[href="##{serial_control}"]))

      assert Floki.find(doc, ".ftn-error-summary span")
             |> Floki.text() =~ "fix the form"

      assert Floki.attribute(find_one(doc, ~s([id="#{serial_control}"])), "aria-invalid") ==
               ["true"]
    end

    test "a generic source's :hide answer suppresses an error that would otherwise show" do
      definition = nested_definition()

      source = %Formentation.SourceFixture{
        params: %{"serial_number" => "PX", "address" => %{}},
        errors: [serial_number: {"is too short", []}],
        submitted?: true,
        visibility: %{["serial_number"] => :hide}
      }

      form = FormData.to_form(source, as: "payload")

      doc =
        render_component(&Formentation.Phoenix.fields/1, definition: definition, form: form)
        |> parse!()

      serial_control = field_id("payload", ["serial_number"], :control)

      assert Floki.find(doc, ".ftn-errors") == []
      assert Floki.find(doc, ~s(a[href="##{serial_control}"])) == []
      assert Floki.attribute(find_one(doc, ~s([id="#{serial_control}"])), "aria-invalid") == []
    end

    test "both components require an explicit definition for a generic form" do
      definition = nested_definition()

      form =
        FormData.to_form(
          %Formentation.SourceFixture{
            params: %{"serial_number" => "PX-1", "address" => %{}}
          },
          as: "payload"
        )

      assert_raise ArgumentError, ~r/native projected form.*generic form plus definition:/, fn ->
        render_component(&Formentation.Phoenix.fields/1, form: form)
      end

      assert_raise ArgumentError, ~r/native projected form.*generic form plus definition:/, fn ->
        render_component(&Formentation.Phoenix.field/1, form: form, path: ["serial_number"])
      end

      fields_doc =
        render_component(&Formentation.Phoenix.fields/1, definition: definition, form: form)
        |> parse!()

      field_doc =
        render_component(&Formentation.Phoenix.field/1,
          definition: definition,
          form: form,
          path: ["serial_number"]
        )
        |> parse!()

      assert [_] = Floki.find(fields_doc, ~s(input[name="payload[serial_number]"]))
      assert [_] = Floki.find(field_doc, ~s(input[name="payload[serial_number]"]))
    end
  end

  describe "error summary placement" do
    defp summary_forms do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"hours", %{kind: :integer}},
            {"address",
             %{kind: :object, title: "Address", properties: [{"floor", %{kind: :integer}}]}}
          ]
        })

      state =
        Form.transition(Form.new(definition), %Params{
          values: %{"hours" => "5o", "address" => %{"floor" => "3x"}},
          event: :submit
        })

      root = FormData.to_form(state, as: "asset[payload]", id: "asset_payload")
      [address] = FormData.to_form(state, root, :address, [])
      {root, address}
    end

    test "a root form renders the submit-gated summary" do
      {root, _address} = summary_forms()
      doc = render_component(&Formentation.Phoenix.fields/1, form: root) |> parse!()

      assert [_] = Floki.find(doc, ~s(div.ftn-error-summary[role="alert"]))
    end

    test "a nested form renders no summary of its own by default" do
      {_root, address} = summary_forms()
      doc = render_component(&Formentation.Phoenix.fields/1, form: address) |> parse!()

      assert Floki.find(doc, ~s([role="alert"])) == []
      assert [_] = Floki.find(doc, ".ftn-errors")
    end

    test "summary={true} places the summary on a nested form" do
      {_root, address} = summary_forms()

      doc =
        render_component(&Formentation.Phoenix.fields/1, form: address, summary: true) |> parse!()

      assert [_] = Floki.find(doc, ~s(div.ftn-error-summary[role="alert"]))
      assert_all_references_resolve(doc)
    end

    test "summary={false} suppresses the summary on a root form" do
      {root, _address} = summary_forms()

      doc =
        render_component(&Formentation.Phoenix.fields/1, form: root, summary: false) |> parse!()

      assert Floki.find(doc, ~s([role="alert"])) == []
    end
  end

  describe "object summary linking across projection variants (#34)" do
    # address is present but incomplete (street only, geo missing), so it
    # fires its own minProperties issue at ["address"] *and* a descendant
    # "geo is required" issue at ["address", "geo"] — one root issue, one
    # address issue, one geo issue, routed through three render contexts.
    defp nested_object_definition do
      compile_json!(%{
        "type" => "object",
        "minProperties" => 3,
        "required" => ["address"],
        "properties" => %{
          "title" => %{"type" => "string"},
          "address" => %{
            "type" => "object",
            "title" => "Address",
            "minProperties" => 2,
            "required" => ["geo"],
            "properties" => %{
              "street" => %{"type" => "string", "minLength" => 1},
              "geo" => %{
                "type" => "object",
                "required" => ["lat"],
                "properties" => %{"lat" => %{"type" => "string", "minLength" => 1}}
              }
            }
          }
        }
      })
    end

    defp nested_object_forms do
      definition = nested_object_definition()

      state =
        Form.new(definition)
        |> Form.transition(%Params{
          values: %{"title" => "t", "address" => %{"street" => "Elm"}},
          event: :submit
        })

      root = FormData.to_form(state, as: "payload")
      [address] = FormData.to_form(state, root, :address, [])
      {root, address}
    end

    defp unlinked_summary_entries(doc) do
      doc |> Floki.find(".ftn-error-summary li") |> Enum.filter(&(Floki.find(&1, "a") == []))
    end

    test "a whole-form render links the object issue and leaves the root issue unlinked" do
      {root, _address} = nested_object_forms()
      doc = render_fields(nested_object_definition(), root) |> parse!()

      target = DOMIdentity.object("payload", InstancePath.new!(["address"]), :container)

      link = find_one(doc, ~s(a[href="##{target}"]))
      assert Floki.text(link) =~ "Address"

      fieldset = find_one(doc, ~s(fieldset[id="#{target}"]))
      assert Floki.attribute(fieldset, "tabindex") == ["-1"]

      # The root-of-form issue (minProperties on the whole payload) has no
      # rendered fieldset of its own, so it stays a plain, unlinked entry.
      assert [span] = unlinked_summary_entries(doc)
      assert Floki.text(span) =~ "at least 3 properties"

      assert_all_references_resolve(doc)
      assert_no_duplicate_ids(doc)
    end

    test "a nested projected form's own root issue stays unlinked under summary={true}" do
      {_root, address} = nested_object_forms()

      doc =
        render_component(&Formentation.Phoenix.fields/1, form: address, summary: true) |> parse!()

      # fields/1 never renders the projected root's own fieldset, so
      # address's own minProperties issue has nothing to link to here.
      assert [span] = unlinked_summary_entries(doc)
      assert Floki.text(span) =~ "at least 2 properties"
      assert_all_references_resolve(doc)
    end

    test "a nested projected form's descendant object issue links using its own namespace" do
      {_root, address} = nested_object_forms()

      doc =
        render_component(&Formentation.Phoenix.fields/1, form: address, summary: true) |> parse!()

      target =
        DOMIdentity.object("payload_address", InstancePath.new!(["address", "geo"]), :container)

      link = find_one(doc, ~s(a[href="##{target}"]))
      assert Floki.text(link) == "Geo: property 'geo' is required"

      fieldset = find_one(doc, ~s(fieldset[id="#{target}"]))
      assert Floki.attribute(fieldset, "tabindex") == ["-1"]

      assert_all_references_resolve(doc)
      assert_no_duplicate_ids(doc)
    end

    test "an explicit dom_namespace changes the summary link and target together" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"address", %{kind: :object, properties: [{"street", %{kind: :string}}]}}
          ]
        })

      source = %Formentation.SourceFixture{
        params: %{"address" => %{"street" => "Elm"}},
        submitted?: true,
        issues:
          {:ok,
           [%StateView.Issue{path: InstancePath.new!(["address"]), message: "is incomplete"}]}
      }

      doc =
        render_component(&Formentation.Phoenix.fields/1,
          definition: definition,
          form: FormData.to_form(source, as: "payload"),
          dom_namespace: "asset_payload"
        )
        |> parse!()

      target = DOMIdentity.object("asset_payload", InstancePath.new!(["address"]), :container)
      link = find_one(doc, ~s(a[href="##{target}"]))
      assert Floki.text(link) =~ "is incomplete"
      find_one(doc, ~s(fieldset[id="#{target}"]))

      # The Phoenix transport name is untouched by the DOM namespace override.
      assert [_] = Floki.find(doc, ~s(input[name="payload[address][street]"]))
      assert_all_references_resolve(doc)
    end

    test "an object issue inside a presentation group links to the object, not the group" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"address",
             %{
               kind: :object,
               properties: [{"street", %{kind: :string}}],
               groups: [%{id: "details", title: "Details", fields: ["street"]}]
             }}
          ]
        })

      source = %Formentation.SourceFixture{
        params: %{"address" => %{"street" => "Elm"}},
        submitted?: true,
        issues:
          {:ok,
           [%StateView.Issue{path: InstancePath.new!(["address"]), message: "is incomplete"}]}
      }

      doc = parse!(render_fields(definition, FormData.to_form(source, as: "payload")))

      object_target = DOMIdentity.object("payload", InstancePath.new!(["address"]), :container)

      group_target =
        DOMIdentity.group(
          "payload",
          "/address#details",
          InstancePath.new!(["address"]),
          :container
        )

      link = find_one(doc, ~s(a[href="##{object_target}"]))
      assert Floki.text(link) =~ "is incomplete"
      assert Floki.find(doc, ~s(a[href="##{group_target}"])) == []

      object_fieldset = find_one(doc, ~s(fieldset[id="#{object_target}"]))
      assert Floki.attribute(object_fieldset, "tabindex") == ["-1"]

      group_fieldset = find_one(doc, ~s(fieldset[id="#{group_target}"]))
      assert Floki.attribute(group_fieldset, "tabindex") == []

      assert_all_references_resolve(doc)
      assert_no_duplicate_ids(doc)
    end
  end

  describe "field/1" do
    test "renders a nested object's own fieldset at the relative root path" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"serial_number", %{kind: :string}},
            {"address",
             %{
               kind: :object,
               title: "Address",
               help: "Where it lives.",
               properties: [{"street", %{kind: :string}}]
             }}
          ]
        })

      form_state = Form.new(definition, %{"address" => %{"street" => "Elm"}})
      root = FormData.to_form(form_state, as: "asset[payload]", id: "asset_payload")
      [address] = FormData.to_form(form_state, root, :address, [])

      doc = render_component(&Formentation.Phoenix.field/1, form: address, path: []) |> parse!()

      assert [_] = Floki.find(doc, "fieldset")
      assert Floki.text(find_one(doc, "legend")) |> String.trim() == "Address"
      assert Floki.text(find_one(doc, ".ftn-group-help")) |> String.trim() == "Where it lives."

      assert [_] = Floki.find(doc, ~s(input[name="asset[payload][address][street]"]))
      assert Floki.find(doc, ~s(input[name="asset[payload][serial_number]"])) == []

      assert_all_references_resolve(doc)
    end

    test "renders root help when explicitly projecting the root subtree" do
      definition = compile!(%{kind: :object, help: "Root help.", properties: []})
      form = FormData.to_form(Form.new(definition), as: "payload")

      doc =
        render_component(&Formentation.Phoenix.field/1,
          definition: definition,
          form: form,
          path: []
        )
        |> parse!()

      root_id = DOMIdentity.object("payload", InstancePath.new!([]), :container)
      root_help_id = DOMIdentity.object("payload", InstancePath.new!([]), :help)

      assert Floki.text(find_one(doc, ".ftn-group-help")) |> String.trim() == "Root help."
      assert describedby(doc, root_id) == [root_help_id]
    end

    test "renders a single field subtree at an instance path" do
      definition = nested_definition()
      form = FormData.to_form(Form.new(definition), as: "payload", id: "payload")

      html =
        render_component(&Formentation.Phoenix.field/1,
          definition: definition,
          form: form,
          path: ["address", "street"]
        )

      doc = parse!(html)

      street =
        find_one(doc, ~s(input[id="#{field_id("payload", ["address", "street"], :control)}"]))

      assert Floki.attribute(street, "name") == ["payload[address][street]"]
      assert Floki.find(doc, ~s([id="#{field_id("payload", ["serial_number"], :control)}"])) == []
    end

    test "raises on an unknown path" do
      definition = nested_definition()
      form = FormData.to_form(Form.new(definition), as: "payload")

      assert_raise ArgumentError, ~r/no node at instance path/, fn ->
        render_component(&Formentation.Phoenix.field/1,
          definition: definition,
          form: form,
          path: ["nope"]
        )
      end
    end
  end

  describe "escaping (contract item 7)" do
    test "hostile schema text never becomes markup" do
      hostile = "<script>alert('x')</script>"

      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"a", %{kind: :string, title: hostile, help: hostile}},
            {"b", %{kind: :string, one_of: [hostile]}}
          ],
          groups: [%{id: "g", title: hostile, fields: ["b"]}]
        })

      form = FormData.to_form(Form.new(definition), as: "payload")
      html = render_fields(definition, form)

      refute html =~ "<script>"
      assert parse!(html) |> Floki.find("script") == []
    end

    test "hostile nested object help never becomes group markup" do
      hostile = "</p><script>alert('group')</script>"

      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"address",
             %{kind: :object, help: hostile, properties: [{"street", %{kind: :string}}]}}
          ]
        })

      html =
        definition
        |> Form.new()
        |> FormData.to_form(as: "payload")
        |> then(&render_fields(definition, &1))

      refute html =~ "<script>"
      assert parse!(html) |> Floki.find("script") == []
    end
  end
end
