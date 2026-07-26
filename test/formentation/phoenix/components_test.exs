defmodule Formentation.Phoenix.ComponentsTest do
  use ExUnit.Case, async: true

  doctest Formentation.Phoenix

  import Formentation.HTMLAssertions
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Formentation.{Form, Params}
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

      serial = find_one(doc, "input#asset_payload_serial_number")
      assert Floki.attribute(serial, "name") == ["asset[payload][serial_number]"]
      assert_labelled(doc, "asset_payload_serial_number")

      street = find_one(doc, "input#asset_payload_address_street")
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
      find_one(doc, "a[href='#payload_operating_hours']")
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
      assert ids == ["payload_a", "payload_d", "payload_b", "payload_c"]
      refute Enum.any?(names, &String.contains?(&1, "late"))
    end

    test "before any action there is no summary and no visible error" do
      definition = nested_definition()
      form = FormData.to_form(Form.new(definition), [])
      doc = parse!(render_fields(definition, form))

      assert Floki.find(doc, ".ftn-error-summary") == []
      assert Floki.find(doc, ".ftn-errors") == []
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
      street = find_one(doc, "input#payload_address_street")
      assert Floki.attribute(street, "name") == ["payload[address][street]"]
      assert Floki.find(doc, "#payload_serial_number") == []
    end

    test "raises on an unknown path" do
      definition = nested_definition()
      form = FormData.to_form(Form.new(definition), [])

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

      form = FormData.to_form(Form.new(definition), [])
      html = render_fields(definition, form)

      refute html =~ "<script>"
      assert parse!(html) |> Floki.find("script") == []
    end
  end
end
