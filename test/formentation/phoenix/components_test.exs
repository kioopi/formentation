defmodule Formentation.Phoenix.ComponentsTest do
  use ExUnit.Case, async: true

  doctest Formentation.Phoenix

  import Formentation.HTMLAssertions
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Formentation.{Form, InstancePath, Params}
  alias Formentation.Phoenix.DOMIdentity
  alias Phoenix.HTML.FormData

  defp compile!(declaration) do
    {:ok, definition, _diagnostics} =
      Formentation.compile(declaration, adapter: Formentation.Source.Map)

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

  describe "fields/1" do
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

      serial = find_one(doc, "input#ftn--asset_payload--field--control--serial_number")
      assert Floki.attribute(serial, "name") == ["asset[payload][serial_number]"]
      assert_labelled(doc, "ftn--asset_payload--field--control--serial_number")

      street = find_one(doc, "input#ftn--asset_payload--field--control--address--street")
      assert Floki.attribute(street, "name") == ["asset[payload][address][street]"]
      assert Floki.attribute(street, "value") == ["Elm"]

      assert_no_duplicate_ids(doc)
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
      find_one(doc, "a[href='#ftn--payload--field--control--operating_hours']")
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

      assert ids == [
               "ftn--payload--field--control--a",
               "ftn--payload--field--control--d",
               "ftn--payload--field--control--b",
               "ftn--payload--field--control--c"
             ]

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

      input = find_one(doc, "#ftn--asset_payload--field--control--serial_number")
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
            {"condition--option_0", %{kind: :string}}
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

      assert Enum.uniq([
               notes_control,
               notes_help,
               notes_help_control,
               notes_errors_control,
               flat_path,
               nested_path,
               radio_option,
               option_like_field
             ])
             |> length() == 8

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
    end
  end

  describe "field/1" do
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
      street = find_one(doc, "input#ftn--payload--field--control--address--street")
      assert Floki.attribute(street, "name") == ["payload[address][street]"]
      assert Floki.find(doc, "#ftn--payload--field--control--serial_number") == []
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
  end
end
