defmodule Formentation.Phoenix.ThemeTest do
  use ExUnit.Case, async: true

  doctest Formentation.Phoenix.Theme.Reference

  import Formentation.HTMLAssertions
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Formentation.InstancePath
  alias Formentation.Phoenix.{DOMIdentity, RenderNode}
  alias Formentation.Phoenix.Theme.Reference

  defp field_id(path, part), do: DOMIdentity.field("payload", InstancePath.new!(path), part)

  defp group_id(layout_id, part),
    do: DOMIdentity.group("payload", layout_id, InstancePath.new!([]), part)

  defp form_field(overrides \\ []) do
    defaults = [id: "notes", name: "notes", value: nil, errors: [], field: :notes, form: nil]
    struct!(Phoenix.HTML.FormField, Keyword.merge(defaults, overrides))
  end

  defp field_node(overrides \\ []) do
    defaults = [
      widget: :text_input,
      field: form_field(),
      label: "Notes",
      dom: %RenderNode.FieldDOM{
        control: field_id(["notes"], :control),
        container: field_id(["notes"], :container),
        help: field_id(["notes"], :help),
        errors: field_id(["notes"], :errors),
        options: []
      },
      help: nil,
      options: nil,
      validations: [],
      errors: [],
      show_errors?: false,
      read_only?: false
    ]

    struct!(RenderNode.Field, Keyword.merge(defaults, overrides))
  end

  defp render_field(overrides) do
    parse!(render_component(&Reference.field/1, node: field_node(overrides)))
  end

  defp checkbox_node(overrides \\ []) do
    defaults = [
      widget: :checkbox,
      field: form_field(id: "insulation_ok", name: "insulation_ok", field: :insulation_ok),
      label: "Insulation test passed",
      dom: %RenderNode.FieldDOM{
        control: DOMIdentity.field("payload", InstancePath.new!(["insulation_ok"]), :control),
        container: DOMIdentity.field("payload", InstancePath.new!(["insulation_ok"]), :container),
        help: DOMIdentity.field("payload", InstancePath.new!(["insulation_ok"]), :help),
        errors: DOMIdentity.field("payload", InstancePath.new!(["insulation_ok"]), :errors),
        options: []
      }
    ]

    field_node(Keyword.merge(defaults, overrides))
  end

  defp select_node(overrides) do
    defaults = [
      widget: :select,
      field: form_field(id: "condition", name: "condition", field: :condition),
      label: "Condition",
      options: ["good", "worn", "defective"],
      dom: %RenderNode.FieldDOM{
        control: DOMIdentity.field("payload", InstancePath.new!(["condition"]), :control),
        container: DOMIdentity.field("payload", InstancePath.new!(["condition"]), :container),
        help: DOMIdentity.field("payload", InstancePath.new!(["condition"]), :help),
        errors: DOMIdentity.field("payload", InstancePath.new!(["condition"]), :errors),
        options:
          Enum.map(
            0..2,
            &DOMIdentity.field("payload", InstancePath.new!(["condition"]), {:option, &1})
          )
      }
    ]

    field_node(Keyword.merge(defaults, overrides))
  end

  defp radio_node(overrides) do
    defaults = [
      widget: :radio_group,
      field: form_field(id: "condition", name: "condition", field: :condition),
      label: "Condition",
      options: ["good", "worn"],
      dom: %RenderNode.FieldDOM{
        control: DOMIdentity.field("payload", InstancePath.new!(["condition"]), :control),
        container: DOMIdentity.field("payload", InstancePath.new!(["condition"]), :container),
        help: DOMIdentity.field("payload", InstancePath.new!(["condition"]), :help),
        errors: DOMIdentity.field("payload", InstancePath.new!(["condition"]), :errors),
        options: [
          field_id(["condition"], {:option, 0}),
          field_id(["condition"], {:option, 1})
        ]
      }
    ]

    field_node(Keyword.merge(defaults, overrides))
  end

  describe "the field wrapper (text input)" do
    test "labels the control and renders name and value" do
      doc = render_field(field: form_field(value: "PX-2044"))

      assert_labelled(doc, field_id(["notes"], :control))
      input = find_one(doc, "div.ftn-field input[type=text]")
      assert Floki.attribute(input, "name") == ["notes"]
      assert Floki.attribute(input, "value") == ["PX-2044"]
      assert describedby(doc, field_id(["notes"], :control)) == []
      assert Floki.attribute(input, "aria-invalid") == []
    end

    test "links help text through aria-describedby" do
      doc = render_field(help: "Visible to all technicians.")

      help = find_one(doc, ~s(p.ftn-help[id="#{field_id(["notes"], :help)}"]))
      assert Floki.text(help) == "Visible to all technicians."

      assert describedby(doc, field_id(["notes"], :control)) == [field_id(["notes"], :help)]
    end

    test "renders visible errors linked and flagged" do
      doc =
        render_field(
          help: "Some help.",
          errors: [{"is too short", code: :min_length, source: :validation}],
          show_errors?: true
        )

      errors = find_one(doc, ~s(ul.ftn-errors[id="#{field_id(["notes"], :errors)}"]))
      assert Floki.text(errors) =~ "is too short"

      assert describedby(doc, field_id(["notes"], :control)) == [
               field_id(["notes"], :help),
               field_id(["notes"], :errors)
             ]

      input = find_one(doc, "input")
      assert Floki.attribute(input, "aria-invalid") == ["true"]
    end

    test "stored-but-hidden errors render nothing" do
      doc =
        render_field(
          errors: [{"is too short", code: :min_length, source: :validation}],
          show_errors?: false
        )

      assert Floki.find(doc, ".ftn-errors") == []
      assert Floki.attribute(find_one(doc, "input"), "aria-invalid") == []
    end

    test "applies validations as progressive-hint attributes" do
      doc = render_field(validations: [required: true, minlength: 4])

      input = find_one(doc, "input")
      assert Floki.attribute(input, "required") == ["required"]
      assert Floki.attribute(input, "minlength") == ["4"]
    end

    test "read-only renders the readonly attribute" do
      doc = render_field(read_only?: true)
      assert Floki.attribute(find_one(doc, "input"), "readonly") == ["readonly"]
    end
  end

  describe "text-like widgets" do
    test "typed inputs carry their HTML type" do
      for {widget, type} <- [
            date_input: "date",
            email_input: "email",
            url_input: "url"
          ] do
        doc = render_field(widget: widget)
        assert [_] = Floki.find(doc, "input[type=#{type}]")
      end
    end

    test "number widgets render as text with a numeric inputmode, not type=number" do
      doc = render_field(widget: :number_input)
      input = find_one(doc, "input")
      assert Floki.attribute(input, "type") == ["text"]
      assert Floki.attribute(input, "inputmode") == ["numeric"]
    end

    test "a failed decode's raw text stays in a number input" do
      doc = render_field(widget: :number_input, field: form_field(value: "51o2"))
      assert Floki.attribute(find_one(doc, "input"), "value") == ["51o2"]
    end

    test "number widgets drop min/max/step but keep required" do
      doc =
        render_field(
          widget: :number_input,
          validations: [required: true, min: 0, max: 100, step: 1]
        )

      input = find_one(doc, "input")
      assert Floki.attribute(input, "required") == ["required"]
      assert Floki.attribute(input, "min") == []
      assert Floki.attribute(input, "max") == []
      assert Floki.attribute(input, "step") == []
    end

    test "a plain text widget renders without an inputmode attribute" do
      doc = render_field(widget: :text_input)
      assert Floki.attribute(find_one(doc, "input"), "inputmode") == []
    end

    test "textarea renders the value escaped as content, readonly when read-only" do
      html =
        render_component(&Reference.field/1,
          node:
            field_node(
              widget: :textarea,
              field: form_field(value: "Runs <fine>."),
              read_only?: true
            )
        )

      assert html =~ "Runs &lt;fine&gt;."

      doc = parse!(html)
      textarea = find_one(doc, ~s(textarea[id="#{field_id(["notes"], :control)}"]))
      assert Floki.attribute(textarea, "readonly") == ["readonly"]
      assert_labelled(doc, field_id(["notes"], :control))
    end

    test "textarea escapes hostile content — no tag breakout" do
      html =
        render_component(&Reference.field/1,
          node:
            field_node(
              widget: :textarea,
              field: form_field(value: "</textarea><script>alert(1)</script>")
            )
        )

      refute html =~ "<script>"
      assert parse!(html) |> Floki.find("script") == []
    end

    test "a hidden input renders bare — no wrapper, no label" do
      doc = render_field(widget: :hidden_input, field: form_field(value: "abc"))

      assert Floki.find(doc, ".ftn-field") == []
      assert Floki.find(doc, "label") == []
      input = find_one(doc, "input[type=hidden]")
      assert Floki.attribute(input, "value") == ["abc"]
      assert Floki.attribute(input, "name") == ["notes"]
      assert Floki.attribute(input, "id") == [field_id(["notes"], :control)]
    end
  end

  describe "checkbox (D-011 and D-016)" do
    test "an editable checkbox carries the hidden false input first" do
      doc = parse!(render_component(&Reference.field/1, node: checkbox_node()))

      # D-011 conformance: without the hidden input, unchecking cannot submit.
      [hidden, checkbox] = Floki.find(doc, "input")
      assert Floki.attribute(hidden, "type") == ["hidden"]
      assert Floki.attribute(hidden, "name") == ["insulation_ok"]
      assert Floki.attribute(hidden, "value") == ["false"]
      assert Floki.attribute(checkbox, "type") == ["checkbox"]
      assert Floki.attribute(checkbox, "value") == ["true"]
      assert Floki.attribute(checkbox, "checked") == []
      assert_labelled(doc, field_id(["insulation_ok"], :control))
    end

    test "boolean true and transport 'true' both check the box" do
      for value <- [true, "true"] do
        doc =
          parse!(
            render_component(&Reference.field/1,
              node:
                checkbox_node(
                  field: form_field(id: "insulation_ok", name: "insulation_ok", value: value)
                )
            )
          )

        assert Floki.attribute(find_one(doc, "input[type=checkbox]"), "checked") == ["checked"]
      end
    end

    test "a read-only boolean is a disabled checkbox without the hidden input" do
      # D-016: read-only is server-enforced; no hidden mirror may submit.
      doc = parse!(render_component(&Reference.field/1, node: checkbox_node(read_only?: true)))

      [checkbox] = Floki.find(doc, "input")
      assert Floki.attribute(checkbox, "type") == ["checkbox"]
      assert Floki.attribute(checkbox, "disabled") == ["disabled"]
    end

    test "required never becomes the HTML required attribute on a checkbox" do
      # HTML required on a checkbox means "must be CHECKED" — a different
      # constraint than a required boolean, which D-011's hidden input
      # already satisfies by always submitting true or false.
      doc =
        parse!(
          render_component(&Reference.field/1, node: checkbox_node(validations: [required: true]))
        )

      assert Floki.attribute(find_one(doc, "input[type=checkbox]"), "required") == []
    end
  end

  describe "select" do
    test "always leads with a blank option and marks the current value" do
      doc =
        parse!(
          render_component(&Reference.field/1,
            node:
              select_node(field: form_field(id: "condition", name: "condition", value: "worn"))
          )
        )

      assert_labelled(doc, field_id(["condition"], :control))
      options = Floki.find(doc, ~s(select[id="#{field_id(["condition"], :control)}"] option))
      assert [{"option", _, []} | _] = options
      assert Floki.attribute(hd(options), "value") == [""]
      assert [_, _, _, _] = options

      [selected] = Floki.find(doc, "option[selected]")
      assert Floki.attribute(selected, "value") == ["worn"]
    end

    test "nil selects nothing and read-only disables" do
      doc = parse!(render_component(&Reference.field/1, node: select_node(read_only?: true)))

      select = find_one(doc, "select")
      assert Floki.attribute(select, "disabled") == ["disabled"]
      assert Floki.find(doc, "option[selected]") == []
    end
  end

  describe "radio group" do
    test "renders a fieldset with legend and one labelled radio per option" do
      doc =
        parse!(
          render_component(&Reference.field/1,
            node:
              radio_node(
                field: form_field(id: "condition", name: "condition", value: "worn"),
                help: "Pick one."
              )
          )
        )

      fieldset = find_one(doc, "fieldset.ftn-radio-group")
      assert Floki.attribute(fieldset, "tabindex") == ["-1"]
      assert Floki.text(find_one(doc, "legend")) == "Condition"

      assert Floki.attribute(fieldset, "id") == [
               DOMIdentity.field("payload", InstancePath.new!(["condition"]), :container)
             ]

      assert Floki.attribute(fieldset, "aria-describedby") == [
               field_id(["condition"], :help)
             ]

      radios = Floki.find(doc, "input[type=radio]")
      assert [_, _] = radios
      assert Enum.flat_map(radios, &Floki.attribute(&1, "name")) == ["condition", "condition"]
      assert_labelled(doc, field_id(["condition"], {:option, 0}))
      assert_labelled(doc, field_id(["condition"], {:option, 1}))

      [checked] = Floki.find(doc, "input[type=radio][checked]")
      assert Floki.attribute(checked, "value") == ["worn"]

      # No outer label element: the legend names the group.
      assert Floki.find(doc, "div.ftn-field > label") == []
    end

    test "read-only disables every radio" do
      doc = parse!(render_component(&Reference.field/1, node: radio_node(read_only?: true)))

      radios = Floki.find(doc, "input[type=radio]")
      assert [_, _] = radios

      for radio <- radios do
        assert Floki.attribute(radio, "disabled") == ["disabled"]
      end
    end

    test "radio group is a radiogroup and carries required on its inputs" do
      doc =
        parse!(
          render_component(&Reference.field/1, node: radio_node(validations: [required: true]))
        )

      fieldset = find_one(doc, "fieldset.ftn-radio-group")
      assert Floki.attribute(fieldset, "role") == ["radiogroup"]

      radios = Floki.find(doc, "input[type=radio]")
      assert radios != []
      assert Enum.all?(radios, fn radio -> Floki.attribute(radio, "required") != [] end)
    end

    test "radio group applies only :required, never other constraint attrs" do
      doc =
        parse!(
          render_component(&Reference.field/1,
            node: radio_node(validations: [required: true, minlength: 4])
          )
        )

      assert Floki.find(doc, "input[type=radio][minlength]") == []
    end
  end

  describe "node dispatch and groups" do
    test "a group renders a fieldset with legend and its children" do
      group = %RenderNode.Group{
        legend: "Electrical",
        help: "Measurements and safety checks.",
        dom: %RenderNode.GroupDOM{
          container: group_id("electrical", :container),
          help: group_id("electrical", :help)
        },
        children: [field_node(), checkbox_node()]
      }

      doc = parse!(render_component(&Reference.node/1, node: group))

      fieldset = find_one(doc, "fieldset.ftn-group")
      assert Floki.text(find_one(fieldset, "legend")) == "Electrical"

      assert Floki.text(find_one(fieldset, ".ftn-group-help")) |> String.trim() ==
               "Measurements and safety checks."

      assert describedby(doc, group.dom.container) == [group.dom.help]
      assert [_, _] = Floki.find(doc, "fieldset.ftn-group div.ftn-field")
    end

    test "a group without help omits the help element and describedby attribute" do
      group = %RenderNode.Group{
        legend: "Electrical",
        dom: %RenderNode.GroupDOM{
          container: group_id("electrical", :container),
          help: group_id("electrical", :help)
        }
      }

      doc = parse!(render_component(&Reference.node/1, node: group))

      assert Floki.find(doc, ".ftn-group-help") == []
      assert describedby(doc, group.dom.container) == []
      assert [_] = Floki.find(doc, ~s(fieldset[id="#{group.dom.container}"]))
    end

    test "an empty binary group help remains associated" do
      group = %RenderNode.Group{
        legend: "Electrical",
        help: "",
        dom: %RenderNode.GroupDOM{
          container: group_id("electrical", :container),
          help: group_id("electrical", :help)
        }
      }

      doc = parse!(render_component(&Reference.node/1, node: group))

      assert [_] = Floki.find(doc, ~s(p[id="#{group.dom.help}"].ftn-group-help))
      assert describedby(doc, group.dom.container) == [group.dom.help]
    end

    test "group help is escaped" do
      help = "</p><script>alert('group')</script>"

      group = %RenderNode.Group{
        legend: "Electrical",
        help: help,
        dom: %RenderNode.GroupDOM{
          container: group_id("electrical", :container),
          help: group_id("electrical", :help)
        }
      }

      doc = parse!(render_component(&Reference.node/1, node: group))

      assert Floki.find(doc, "script") == []
      assert Floki.text(find_one(doc, ".ftn-group-help")) |> String.trim() == help
    end

    test "nested groups recurse" do
      inner = %RenderNode.Group{
        legend: "Details",
        help: "Inner help.",
        dom: %RenderNode.GroupDOM{
          container: group_id("inner", :container),
          help: group_id("inner", :help)
        },
        children: [field_node()]
      }

      outer = %RenderNode.Group{
        legend: "Details",
        help: "Outer help.",
        dom: %RenderNode.GroupDOM{
          container: group_id("outer", :container),
          help: group_id("outer", :help)
        },
        children: [inner]
      }

      doc = parse!(render_component(&Reference.node/1, node: outer))

      assert [_outer, _inner] = Floki.find(doc, "fieldset.ftn-group")

      assert doc |> Floki.find("fieldset.ftn-group legend") |> Enum.map(&Floki.text/1) == [
               "Details",
               "Details"
             ]

      assert_no_duplicate_ids(doc)
      assert describedby(doc, outer.dom.container) == [outer.dom.help]
      assert describedby(doc, inner.dom.container) == [inner.dom.help]
    end
  end

  describe "error summary" do
    test "renders nothing for an empty summary" do
      assert render_component(&Reference.error_summary/1, summary: []) |> parse!() == []
    end

    test "links field entries to their controls and lists root entries plain" do
      summary = [
        %{id: "serial_number", label: "Serial number", message: "is too short"},
        %{id: nil, label: nil, message: "the instance is inconsistent"}
      ]

      doc = parse!(render_component(&Reference.error_summary/1, summary: summary))

      alert = find_one(doc, "div.ftn-error-summary[role=alert]")
      assert Floki.text(alert) =~ "is too short"

      link = find_one(doc, "a[href='#serial_number']")
      assert Floki.text(link) =~ "Serial number"

      assert [_, _] = Floki.find(doc, "li")
      assert Floki.find(doc, "li a") |> length() == 1
    end

    test "renders root entries (nil id) as plain spans" do
      html =
        render_component(&Reference.error_summary/1,
          summary: [%{id: nil, label: nil, message: "root problem"}]
        )

      doc = parse!(html)
      assert [span] = Floki.find(doc, ".ftn-error-summary li span")
      assert Floki.text(span) == "root problem"
      assert Floki.find(doc, ".ftn-error-summary li a") == []
    end
  end
end
