defmodule Formentation.Phoenix.RenderPreparationTest.ProjectorAdapter do
  @moduledoc """
  Keeps the pre-rename `Projector.project/2,3` and `project_at/3,4` call
  shapes working so ~1200 lines of behavioural assertions did not have to be
  rewritten under the rename.

  Passing `definition:` does **not** select the generic branch.
  `resolve_context/2` dispatches on `ProjectedForm.native_context/1` first, so
  a form whose source is a `%Formentation.Form{}` takes the **native** branch
  regardless, and the shim's explicit definition is then checked by
  `validate_native_definition!/2` as a matching redundant definition. Most of
  this file's forms are native, so the bulk of preparation coverage exercises
  native derivation plus that redundancy check. Only the map-source and
  `SourceFixture` forms reach the generic branch — which is where the
  `definition:` requirement itself is proved.
  """

  alias Formentation.Phoenix.RenderPreparation

  def project(definition, form), do: RenderPreparation.prepare(form, definition: definition)

  def project(definition, form, opts),
    do: RenderPreparation.prepare(form, Keyword.put(opts, :definition, definition))

  def project_at(definition, form, path),
    do: RenderPreparation.prepare_at(form, path, definition: definition)

  def project_at(definition, form, path, opts),
    do: RenderPreparation.prepare_at(form, path, Keyword.put(opts, :definition, definition))
end

defmodule Formentation.Phoenix.RenderPreparationTest do
  use ExUnit.Case, async: true

  import Formentation.Test.FormHelpers

  doctest Formentation.Phoenix.RenderPreparation

  alias Formentation.Definition.Finalizer
  alias Formentation.{Form, InstancePath, NodeId, TemplatePath}
  alias Formentation.Phoenix.{DOMIdentity, RenderNode, RenderPlan, RenderPreparation}
  alias Formentation.Phoenix.RenderPreparationTest.ProjectorAdapter, as: Projector
  alias Formentation.Presentation, as: NativePresentation
  alias Formentation.Semantic
  alias Phoenix.HTML.FormData

  defp compile!(declaration) do
    {:ok, definition, _diagnostics} =
      Formentation.compile(declaration, adapter: Formentation.Source.Map)

    definition
  end

  defp compile_json!(schema) do
    {:ok, definition, _diagnostics} =
      Formentation.compile(schema, adapter: Formentation.JSONSchema)

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

  defp nested_projection_definition do
    compile!(%{
      kind: :object,
      properties: [
        {"title", %{kind: :string}},
        {"address",
         %{
           kind: :object,
           title: "Address",
           help: "Where it lives.",
           properties: [{"street", %{kind: :string}}]
         }}
      ]
    })
  end

  defp nested_projection_forms do
    definition = nested_projection_definition()
    state = Form.new(definition, %{"title" => "root", "address" => %{"street" => "Elm"}})
    root = FormData.to_form(state, as: "asset[payload]", id: "asset_payload")
    [address] = FormData.to_form(state, root, :address, [])
    {root, address}
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

    {definition, FormData.to_form(form_state, as: "payload")}
  end

  describe "project/2 with flat scalar fields" do
    test "emits one component-ready render node per field, in order" do
      definition = flat_definition()

      form =
        FormData.to_form(Form.new(definition, %{"serial_number" => "PX-2044"}), as: "payload")

      plan = Projector.project(definition, form)

      assert %RenderPlan{root: %RenderNode.Group{} = root, summary: [], diagnostics: []} = plan
      assert root.legend == "/"

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

    test "prepares exact field and root identities from the form namespace" do
      definition = flat_definition()
      form = FormData.to_form(Form.new(definition), as: "payload")

      plan = Projector.project(definition, form)
      [serial | _] = plan.root.children

      root_path = InstancePath.new!([])
      serial_path = InstancePath.new!(["serial_number"])

      assert plan.root.dom.container == DOMIdentity.object("payload", root_path, :container)
      assert plan.root.dom.help == DOMIdentity.object("payload", root_path, :help)
      assert serial.dom.control == DOMIdentity.field("payload", serial_path, :control)
      assert serial.dom.container == DOMIdentity.field("payload", serial_path, :container)
      assert serial.dom.help == DOMIdentity.field("payload", serial_path, :help)
      assert serial.dom.errors == DOMIdentity.field("payload", serial_path, :errors)
      assert serial.dom.options == []
    end

    test "an explicit namespace overrides the Phoenix form namespace" do
      definition = flat_definition()
      form = FormData.to_form(Form.new(definition), as: "payload")

      [field | _] =
        Projector.project(definition, form, dom_namespace: "asset_payload").root.children

      assert field.dom.control ==
               DOMIdentity.field("asset_payload", InstancePath.new!(["serial_number"]), :control)
    end

    test "raises clearly when no DOM namespace can be resolved" do
      definition = flat_definition()
      form = FormData.to_form(Form.new(definition), [])

      assert_raise ArgumentError,
                   ~r/Formentation cannot mint DOM ids without a namespace/,
                   fn -> Projector.project(definition, form) end
    end

    test "a nil override falls back to the Phoenix form namespace" do
      definition = flat_definition()
      form = FormData.to_form(Form.new(definition), as: "payload")

      assert Projector.project(definition, form, dom_namespace: nil) ==
               Projector.project(definition, form)
    end

    test "an empty explicit override remains invalid" do
      definition = flat_definition()
      form = FormData.to_form(Form.new(definition), as: "payload")

      assert_raise ArgumentError, ~r/non-empty binary namespace/, fn ->
        Projector.project(definition, form, dom_namespace: "")
      end
    end

    test "label falls back to the humanized field name" do
      definition = compile!(%{kind: :object, properties: [{"serial_number", %{kind: :string}}]})
      form = FormData.to_form(Form.new(definition), as: "payload")

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

      form = FormData.to_form(form_state, as: "payload")
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
    form = FormData.to_form(Form.new(definition), as: "payload")
    Projector.project(definition, form)
  end

  defp single_widget(spec) do
    plan = single_field_plan(spec)
    [%RenderNode.Field{widget: widget}] = plan.root.children
    {widget, plan.diagnostics}
  end

  describe "native and generic preparation contexts" do
    test "derives the definition from a native root form" do
      definition = flat_definition()
      form = FormData.to_form(Form.new(definition), as: "payload")

      assert %RenderPlan{} = RenderPreparation.prepare(form)
    end

    test "requires an explicit definition for a generic form" do
      form = FormData.to_form(%{}, as: "payload")

      assert_raise ArgumentError, ~r/native projected form.*generic form plus definition:/, fn ->
        RenderPreparation.prepare(form)
      end

      assert %RenderPlan{} = RenderPreparation.prepare(form, definition: flat_definition())
    end

    test "rejects an explicit definition that differs from a native form source" do
      native_definition = flat_definition()
      other_definition = compile!(%{kind: :object, properties: [{"name", %{kind: :string}}]})
      form = FormData.to_form(Form.new(native_definition), as: "payload")

      assert_raise ArgumentError, ~r/source definition is authoritative.*remove/, fn ->
        RenderPreparation.prepare(form, definition: other_definition)
      end
    end

    test "rejects malformed metadata on a native form instead of treating it as generic" do
      form = FormData.to_form(Form.new(flat_definition()), as: "payload")
      broken = %{form | options: Keyword.delete(form.options, :__formentation__)}

      assert_raise ArgumentError, ~r/not a valid Formentation projection.*rebuild/, fn ->
        RenderPreparation.prepare(broken, definition: flat_definition())
      end
    end

    test "prepares a nested form's own object at the relative root path" do
      {_root, address} = nested_projection_forms()

      node = RenderPreparation.prepare_at(address, [])

      assert %RenderNode.Group{legend: "Address", help: "Where it lives."} = node

      assert node.dom.container ==
               DOMIdentity.object(
                 "asset_payload_address",
                 InstancePath.new!(["address"]),
                 :container
               )

      # The child name is what proves no second nesting happened: a double
      # descent would produce asset[payload][address][address][street].
      assert [%RenderNode.Field{field: %{name: "asset[payload][address][street]"}}] =
               node.children
    end

    test "rejects a projection root that is not an object from both entry points" do
      {root, _address} = nested_projection_forms()

      tampered = %{
        root
        | options: Keyword.put(root.options, :__formentation__, ["address", "street"])
      }

      message = ~r/projected form root \["address", "street"\] is not an object/

      assert_raise ArgumentError, message, fn -> RenderPreparation.prepare(tampered) end
      assert_raise ArgumentError, message, fn -> RenderPreparation.prepare_at(tampered, []) end

      assert_raise ArgumentError, message, fn ->
        RenderPreparation.prepare_at(tampered, ["street"])
      end
    end

    test "rejects a projection root that names nothing or an unsupported node" do
      definition =
        compile_json!(%{
          "type" => "object",
          "properties" => %{
            "title" => %{"type" => "string"},
            "weird" => %{"not" => %{"type" => "string"}}
          }
        })

      root = FormData.to_form(Form.new(definition), as: "payload", id: "payload")

      missing = %{root | options: Keyword.put(root.options, :__formentation__, ["nope"])}
      unsupported = %{root | options: Keyword.put(root.options, :__formentation__, ["weird"])}

      assert_raise ArgumentError, ~r/projected form root \["nope"\] does not exist/, fn ->
        RenderPreparation.prepare(missing)
      end

      assert_raise ArgumentError, ~r/projected form root \["weird"\] is unsupported/, fn ->
        RenderPreparation.prepare(unsupported)
      end

      # Both entry points, since validation now lives in the shared context.
      assert_raise ArgumentError, ~r/projected form root \["nope"\] does not exist/, fn ->
        RenderPreparation.prepare_at(missing, [])
      end

      assert_raise ArgumentError, ~r/projected form root \["weird"\] is unsupported/, fn ->
        RenderPreparation.prepare_at(unsupported, ["anything"])
      end
    end

    test "prepares only a nested form's subtree and resolves relative field paths" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"title", %{kind: :string}},
            {"address", %{kind: :object, properties: [{"street", %{kind: :string}}]}}
          ]
        })

      form_state = Form.new(definition, %{"title" => "root", "address" => %{"street" => "Main"}})
      root = FormData.to_form(form_state, as: "asset[payload]")
      [address] = FormData.to_form(form_state, root, :address, [])

      plan = RenderPreparation.prepare(address)

      assert [%RenderNode.Field{field: %{name: "asset[payload][address][street]"}}] =
               plan.root.children

      assert %RenderNode.Field{field: %{name: "asset[payload][address][street]"}} =
               RenderPreparation.prepare_at(address, ["street"])

      assert_raise ArgumentError, ~r/relative path.*projected root/, fn ->
        RenderPreparation.prepare_at(address, ["title"])
      end
    end

    test "a nested plan's DOM identities carry the nested form's joined id" do
      {root, address} = nested_projection_forms()

      [root_street] =
        RenderPreparation.prepare(root).root.children
        |> Enum.filter(&match?(%RenderNode.Group{}, &1))
        |> Enum.flat_map(& &1.children)

      [nested_street] = RenderPreparation.prepare(address).root.children

      assert root_street.field.name == nested_street.field.name

      assert root_street.dom.control ==
               DOMIdentity.field(
                 "asset_payload",
                 InstancePath.new!(["address", "street"]),
                 :control
               )

      assert nested_street.dom.control ==
               DOMIdentity.field(
                 "asset_payload_address",
                 InstancePath.new!(["address", "street"]),
                 :control
               )
    end

    test "resolves a relative path deeper than the projected root by one level" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"address",
             %{
               kind: :object,
               properties: [
                 {"geo", %{kind: :object, properties: [{"lat", %{kind: :number}}]}}
               ]
             }}
          ]
        })

      state = Form.new(definition, %{"address" => %{"geo" => %{"lat" => 51.5}}})
      root = FormData.to_form(state, as: "asset[payload]", id: "asset_payload")
      [address] = FormData.to_form(state, root, :address, [])

      node = RenderPreparation.prepare_at(address, ["geo", "lat"])

      assert node.field.name == "asset[payload][address][geo][lat]"
      assert node.field.value == "51.5"

      assert node.dom.control ==
               DOMIdentity.field(
                 "asset_payload_address",
                 InstancePath.new!(["address", "geo", "lat"]),
                 :control
               )
    end
  end

  describe "widget resolution" do
    test "retains normalized value type independently from the resolved widget" do
      assert [%RenderNode.Field{widget: :text_input, value_type: :string}] =
               single_field_plan(%{kind: :string}).root.children

      assert [%RenderNode.Field{widget: :checkbox, value_type: :boolean}] =
               single_field_plan(%{kind: :boolean}).root.children

      assert [%RenderNode.Field{widget: :number_input, value_type: :integer}] =
               single_field_plan(%{kind: :integer}).root.children

      assert [%RenderNode.Field{widget: :number_input, value_type: :number}] =
               single_field_plan(%{kind: :number}).root.children
    end

    test "retains numeric value type when widget resolution chooses another control" do
      assert [%RenderNode.Field{widget: :text_input, value_type: :number}] =
               single_field_plan(%{kind: :number, widget: :text}).root.children

      assert [%RenderNode.Field{widget: :select, value_type: :integer}] =
               single_field_plan(%{kind: :integer, one_of: [1, 2]}).root.children

      assert [%RenderNode.Field{widget: :hidden_input, value_type: :number}] =
               single_field_plan(%{kind: :number, hidden: true}).root.children
    end

    test "threads semantic role onto the prepared field" do
      assert [%RenderNode.Field{role: :email}] =
               single_field_plan(%{kind: :string, role: :email}).root.children

      assert [%RenderNode.Field{role: :date}] =
               single_field_plan(%{kind: :string, role: :date}).root.children
    end

    test "threads the inferred semantic role when the source field omits a role" do
      assert [%RenderNode.Field{role: :text}] =
               single_field_plan(%{kind: :string}).root.children
    end

    test "required? defaults to false when the field is not schema-required" do
      assert [%RenderNode.Field{required?: false}] =
               single_field_plan(%{kind: :string}).root.children
    end

    test "threads schema requiredness onto the prepared field, independent of the HTML required attribute" do
      definition =
        compile!(%{
          kind: :object,
          required: ["f"],
          properties: [{"f", %{kind: :string}}]
        })

      form = FormData.to_form(Form.new(definition), as: "payload")
      plan = Projector.project(definition, form)

      # Required string fields keep the empty value schema-valid (D-010), so
      # the compiler intentionally omits the HTML `required` attribute here.
      assert [%RenderNode.Field{required?: true, validations: validations}] = plan.root.children
      refute Keyword.has_key?(validations, :required)
    end

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

    test "prepares one radio option id per option" do
      plan = single_field_plan(%{kind: :string, one_of: ["yes", "no"], widget: :radio})
      [%RenderNode.Field{options: options, dom: dom}] = plan.root.children

      assert dom.options ==
               Enum.map(0..1, fn index ->
                 DOMIdentity.field("payload", InstancePath.new!(["f"]), {:option, index})
               end)

      assert length(dom.options) == length(options)
      assert Enum.uniq(dom.options) == dom.options
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
    test "preserves Map object help in a nested render group" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"address",
             %{
               kind: :object,
               help: "Where the asset is installed.",
               properties: [{"street", %{kind: :string}}]
             }}
          ]
        })

      form = FormData.to_form(Form.new(definition), as: "payload")

      assert %RenderNode.Group{help: "Where the asset is installed."} =
               Projector.project(definition, form).root.children |> List.first()
    end

    test "preserves JSON Schema object descriptions in nested render groups" do
      definition =
        compile_json!(%{
          "type" => "object",
          "properties" => %{
            "address" => %{
              "type" => "object",
              "description" => "Where the asset is installed.",
              "properties" => %{"street" => %{"type" => "string"}}
            }
          }
        })

      form = FormData.to_form(Form.new(definition), as: "payload")

      assert %RenderNode.Group{help: "Where the asset is installed."} =
               Projector.project(definition, form).root.children |> List.first()
    end

    test "preserves root object help in the render plan" do
      definition = compile!(%{kind: :object, help: "Record one pump.", properties: []})
      form = FormData.to_form(Form.new(definition), as: "payload")
      plan = Projector.project(definition, form)

      assert %RenderNode.Group{help: "Record one pump."} = plan.root
      assert Projector.project_at(definition, form, []) == plan.root
    end

    test "preserves native presentation-group help" do
      path = TemplatePath.new!(["serial_number"])
      field = Semantic.Field.new("serial_number", path, :string)
      semantic = Semantic.Object.new(nil, TemplatePath.new!([]), [field])

      presentation =
        NativePresentation.Object.new(semantic.id, [
          NativePresentation.Group.new(
            NodeId.group(TemplatePath.new!([]), "details"),
            [NativePresentation.Field.new(field.id, label: "Serial number")],
            label: "Details",
            help: "Identification details."
          )
        ])

      assert {:ok, definition} = Finalizer.finalize(semantic, presentation)
      form = FormData.to_form(Form.new(definition), as: "payload")

      assert [%RenderNode.Group{help: "Identification details."}] =
               Projector.project(definition, form).root.children
    end

    test "keeps missing group help nil while preparing DOM identities" do
      definition =
        compile!(%{
          kind: :object,
          properties: [{"address", %{kind: :object, properties: []}}]
        })

      form = FormData.to_form(Form.new(definition), as: "payload")

      assert %RenderNode.Group{help: nil, dom: %{container: container, help: help}} =
               Projector.project(definition, form).root.children |> List.first()

      assert is_binary(container)
      assert is_binary(help)
    end

    test "DOM identities are deterministic and independent of display text and sibling order" do
      declaration = fn properties, title ->
        %{
          kind: :object,
          properties: properties,
          groups: [%{id: "panel", title: title, fields: ["a", "b"]}]
        }
      end

      first =
        declaration.(
          [
            {"a", %{kind: :string, title: "Alpha"}},
            {"b", %{kind: :string, title: "Beta"}}
          ],
          "First legend"
        )
        |> compile!()

      second =
        declaration.(
          [
            {"b", %{kind: :string, title: "Different beta"}},
            {"a", %{kind: :string, title: "Different alpha"}}
          ],
          "Changed legend"
        )
        |> compile!()

      # A native source pins its own definition (D-041), so the two-definition
      # comparison below is illegal by construction against one: passing
      # `second` against a form built from `first` makes
      # validate_native_definition!/2 raise. A map source proves the same
      # claim — DOM identities are a pure function of definition structure —
      # and is the only source that can hold both definitions.
      form = FormData.to_form(%{}, as: "payload")
      assert Projector.project(first, form) == Projector.project(first, form)

      identities = fn definition ->
        definition
        |> Projector.project(form)
        |> Map.fetch!(:root)
        |> flatten_fields()
        |> Map.new(&{&1.field.name, &1.dom})
      end

      assert identities.(first) == identities.(second)

      # The native route mints the same identities, so the D-034 claim is not
      # proved only against a source ordinary rendering never uses.
      native_identities =
        Form.new(first)
        |> FormData.to_form(as: "payload")
        |> RenderPreparation.prepare()
        |> Map.fetch!(:root)
        |> flatten_fields()
        |> Map.new(&{&1.field.name, &1.dom})

      assert native_identities == identities.(first)
    end

    test "presentation order can differ from semantic declaration order" do
      definition =
        compile!(%{
          kind: :object,
          properties: [{"a", %{kind: :string}}, {"c", %{kind: :string}}],
          groups: [%{id: "reordered", fields: ["c", "a"]}]
        })

      form = FormData.to_form(Form.new(definition), as: "payload")
      plan = Projector.project(definition, form)

      assert definition |> Formentation.Info.fields() |> Enum.map(& &1.name) == ["a", "c"]

      assert plan.root |> flatten_fields() |> Enum.map(& &1.field.name) == [
               "payload[c]",
               "payload[a]"
             ]
    end

    test "non-adjacent grouped members keep current layout placement and group order" do
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

      form = FormData.to_form(Form.new(definition), as: "payload")
      plan = Projector.project(definition, form)

      assert [
               %RenderNode.Field{field: %{name: "payload[a]"}},
               %RenderNode.Group{legend: "Late", children: grouped},
               %RenderNode.Field{field: %{name: "payload[c]"}}
             ] = plan.root.children

      assert Enum.map(grouped, & &1.field.name) == ["payload[d]", "payload[b]"]
    end

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

    test "nested objects and presentation groups use their full occurrence identities" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"address",
             %{
               kind: :object,
               help: "Where the asset is installed.",
               properties: [{"street", %{kind: :string}}],
               groups: [%{id: "details", title: "Details", fields: ["street"]}]
             }}
          ]
        })

      form = FormData.to_form(Form.new(definition), as: "payload")

      %RenderNode.Group{children: [%RenderNode.Group{} = address]} =
        Projector.project(definition, form).root

      [%RenderNode.Group{} = presentation_group] = address.children

      assert presentation_group.dom.container ==
               DOMIdentity.group(
                 "payload",
                 "/address#details",
                 InstancePath.new!(["address"]),
                 :container
               )

      assert address.dom.container ==
               DOMIdentity.object("payload", InstancePath.new!(["address"]), :container)

      assert Projector.project_at(definition, form, ["address"]) == address
    end

    test "a nested object inside a presentation group still descends semantically" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"title", %{kind: :string}},
            {"details",
             %{
               kind: :object,
               title: "Details",
               properties: [{"width", %{kind: :integer}}]
             }}
          ],
          groups: [%{id: "main", title: "Main", fields: ["details", "title"]}]
        })

      form =
        FormData.to_form(
          Form.new(definition, %{"title" => "Pump", "details" => %{"width" => 12}}),
          as: "payload"
        )

      assert [%RenderNode.Group{legend: "Main", children: [details, title]}] =
               Projector.project(definition, form).root.children

      assert %RenderNode.Group{legend: "Details", children: [width]} = details
      assert width.field.name == "payload[details][width]"
      assert width.field.value == "12"
      assert title.field.name == "payload[title]"
      assert title.field.value == "Pump"
    end

    test "unsupported nodes and hidden read-only fields render nothing" do
      # %{kind: :carousel} compiles to Semantic.Unsupported with an
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

      form = FormData.to_form(Form.new(definition), as: "payload")
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

    test "a grouped scalar path projects without requiring its group location" do
      definition =
        compile!(%{
          kind: :object,
          properties: [{"title", %{kind: :string}}],
          groups: [%{id: "main", fields: ["title"]}]
        })

      form = FormData.to_form(Form.new(definition, %{"title" => "Pump"}), as: "payload")

      assert %RenderNode.Field{field: field} = Projector.project_at(definition, form, ["title"])
      assert field.name == "payload[title]"
      assert field.value == "Pump"
    end

    test "a presentation group id is not a semantic subtree" do
      definition =
        compile!(%{
          kind: :object,
          properties: [{"title", %{kind: :string}}],
          groups: [%{id: "main", fields: ["title"]}]
        })

      form = FormData.to_form(Form.new(definition), as: "payload")

      assert_raise ArgumentError, ~r/no node at instance path/, fn ->
        Projector.project_at(definition, form, ["main"])
      end
    end

    test "an unsupported node's path raises" do
      definition = subtree_definition()
      form = FormData.to_form(Form.new(definition), as: "payload")

      assert_raise ArgumentError, ~r/unsupported/, fn ->
        Projector.project_at(definition, form, ["gadget"])
      end
    end

    test "a hidden read-only field's path renders nothing" do
      definition = subtree_definition()
      form = FormData.to_form(Form.new(definition), as: "payload")

      assert Projector.project_at(definition, form, ["secret"]) == nil
    end
  end

  describe "error visibility and the summary" do
    test "a radio summary targets the rendered radio container" do
      definition =
        compile!(%{
          kind: :object,
          required: ["condition"],
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

      plan = Projector.project(definition, FormData.to_form(source, as: "payload"))
      [%RenderNode.Field{widget: :radio_group, dom: dom}] = plan.root.children

      assert [%{id: summary_target}] = plan.summary
      assert summary_target == dom.container
    end

    test "on submit every field error is visible and summarized" do
      {definition, form} = decode_error_form(:submit)
      plan = Projector.project(definition, form)

      [_serial, hours, _notes] = plan.root.children
      assert hours.show_errors?
      assert [%{id: id, label: "Operating hours", message: message}] = plan.summary
      assert id == hours.dom.control
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
      # `address` is a plain supported `"type": "object"`. Under D-026
      # (issue #1) a required nested object with no content stays genuinely
      # absent from the candidate, so JSV files the `:required` issue at the
      # object's own path, ["address"]. That path resolves to a Semantic.Object,
      # not a Semantic.Field and not a Semantic.Unsupported, so the state view's
      # normalized issue folds into the summary unlinked and unlabelled.
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
      plan = Projector.project(definition, FormData.to_form(form_state, as: "payload"))

      assert [%{id: nil, label: nil, message: message}] = plan.summary
      assert message =~ "required"
    end
  end

  describe "source-neutral submission and visibility" do
    defp scalar_definition do
      compile!(%{
        kind: :object,
        properties: [{"operating_hours", %{kind: :integer, title: "Operating hours"}}]
      })
    end

    # An unused marker makes the Phoenix default answer "hidden", so the
    # only thing that can reveal the error is semantic submission.
    defp unused_params, do: %{"operating_hours" => "51o2", "_unused_operating_hours" => ""}

    defp fixture_form(overrides) do
      source =
        struct!(
          %Formentation.SourceFixture{
            params: unused_params(),
            errors: [operating_hours: {"is invalid", []}],
            action: :commit
          },
          overrides
        )

      Phoenix.HTML.FormData.to_form(source, as: "payload")
    end

    test "a source whose semantic submit is :commit reveals an unused field's error" do
      plan = Projector.project(scalar_definition(), fixture_form(submitted?: true))

      assert [%RenderNode.Field{show_errors?: true}] = plan.root.children
      assert [%{label: "Operating hours", message: "is invalid"}] = plan.summary
    end

    test "the generic fallback does not treat :commit as submitted" do
      form = %{
        Phoenix.HTML.FormData.to_form(unused_params(), as: "payload")
        | action: :commit,
          errors: [operating_hours: {"is invalid", []}]
      }

      plan = Projector.project(scalar_definition(), form)

      assert [%RenderNode.Field{show_errors?: false}] = plan.root.children
      assert plan.summary == []
    end

    test ":show reveals a field error the Phoenix default would hide" do
      form = fixture_form(visibility: %{["operating_hours"] => :show})

      plan = Projector.project(scalar_definition(), form)

      assert [%RenderNode.Field{show_errors?: true}] = plan.root.children
    end

    test ":hide suppresses a field error semantic submission would reveal" do
      form =
        fixture_form(submitted?: true, visibility: %{["operating_hours"] => :hide})

      plan = Projector.project(scalar_definition(), form)

      assert [%RenderNode.Field{show_errors?: false}] = plan.root.children
      assert plan.summary == []
    end

    test "a source with no issue enumeration still projects fields and scalar summaries" do
      plan = Projector.project(scalar_definition(), fixture_form(submitted?: true))

      assert [%RenderNode.Field{}] = plan.root.children
      assert [_] = plan.summary
    end
  end

  describe "normalized non-field issues in the summary" do
    alias Formentation.Phoenix.StateView

    defp issue(segments, message) do
      %StateView.Issue{
        path: Formentation.InstancePath.new!(segments),
        message: message
      }
    end

    defp summary_form(issues, overrides \\ []) do
      source =
        struct!(
          %Formentation.SourceFixture{
            params: %{"operating_hours" => "1"},
            action: :commit,
            submitted?: true,
            issues: {:ok, issues}
          },
          overrides
        )

      Phoenix.HTML.FormData.to_form(source, as: "payload")
    end

    test "a nested plan's summary carries exactly the non-field issues at or under its root" do
      # One fixture, four boundaries relative to the projected root ["address"]:
      #
      #   []                 ancestor of the root  → excluded
      #   ["address"]        the root itself       → included
      #   ["address","geo"]  descendant            → included
      #   ["contact"]        sibling               → excluded
      #
      # The [] and descendant cases are what distinguish ancestor/self
      # semantics from an equality-only filter; both minProperties issues are
      # filed at the *object's own* path, which is what makes them non-field
      # entries rather than per-field errors.
      definition =
        compile_json!(%{
          "type" => "object",
          "minProperties" => 4,
          "required" => ["address", "contact"],
          "properties" => %{
            "title" => %{"type" => "string"},
            "address" => %{
              "type" => "object",
              "title" => "Address",
              "minProperties" => 3,
              "required" => ["geo"],
              "properties" => %{
                "street" => %{"type" => "string", "minLength" => 1},
                "geo" => %{
                  "type" => "object",
                  "required" => ["lat"],
                  "properties" => %{"lat" => %{"type" => "string", "minLength" => 1}}
                }
              }
            },
            "contact" => %{
              "type" => "object",
              "title" => "Contact",
              "required" => ["email"],
              "properties" => %{"email" => %{"type" => "string", "minLength" => 1}}
            }
          }
        })

      form_state =
        submitted_form(Form.new(definition), %{"title" => "t", "address" => %{"street" => "Elm"}})

      root = FormData.to_form(form_state, as: "asset[payload]", id: "asset_payload")
      [address] = FormData.to_form(form_state, root, :address, [])

      assert Enum.map(RenderPreparation.prepare(root).summary, & &1.message) == [
               "value must have at least 4 properties, got 2",
               "value must have at least 3 properties, got 1",
               "property 'geo' is required",
               "property 'contact' is required"
             ]

      # Root-of-form and sibling entries are gone; self and descendant remain,
      # in adapter order — the filter never reorders.
      address_summary = RenderPreparation.prepare(address).summary

      assert Enum.map(address_summary, & &1.message) == [
               "value must have at least 3 properties, got 1",
               "property 'geo' is required"
             ]

      # Both nested entries are unlinked and unlabelled: they name objects, so
      # summary_label/2 returns nil and there is no focusable control to target.
      assert Enum.all?(address_summary, &(&1.label == nil))
    end

    test "a root issue appears once, unlinked, and never enters a field's errors" do
      plan =
        Projector.project(
          scalar_definition(),
          summary_form([issue([], "the whole form is wrong")])
        )

      assert [%{id: nil, label: nil, message: "the whole form is wrong"}] = plan.summary
      assert [%RenderNode.Field{errors: []}] = plan.root.children
    end

    # Spec §7.3, source-neutrally: the supported-nested-object regression
    # elsewhere in this file runs through %Formentation.Form{}, which owns
    # both the group node and the issue. Here the definition is the only
    # thing the source shares with the projector — an Ash- or Ecto-style
    # adapter hands over a group-level issue through issues/2 alone, and
    # it must still be rendered once, unlinked, without reaching the
    # group's fields.
    test "a nested-object issue appears once, unlinked, and leaves the group's fields alone" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"address", %{kind: :object, properties: [{"street", %{kind: :string}}]}}
          ]
        })

      form =
        summary_form([issue(["address"], "is incomplete")],
          params: %{"address" => %{"street" => "Main"}}
        )

      plan = Projector.project(definition, form)

      assert [%{id: nil, label: nil, message: "is incomplete"}] = plan.summary
      assert [%RenderNode.Group{children: [street]}] = plan.root.children
      assert %RenderNode.Field{errors: [], show_errors?: false} = street
      assert street.field.name == "payload[address][street]"
      assert street.field.value == "Main"
    end

    # D-027: an unsupported node carries a name a reader can recognize, so
    # its normalized issue is labelled from it (unlike the root/group case
    # covered above, which stays unlabelled).
    test "an unsupported node's issue is labelled with its humanized name" do
      definition =
        compile!(%{
          kind: :object,
          properties: [{"gadget", %{kind: :carousel}}, {"name", %{kind: :string}}]
        })

      plan =
        Projector.project(
          definition,
          summary_form([issue(["gadget"], "cannot be repaired here")])
        )

      assert [%{id: nil, label: "Gadget", message: "cannot be repaired here"}] = plan.summary
    end

    test "an issue whose path resolves to a scalar field is not duplicated beside field.errors" do
      form =
        summary_form([issue(["operating_hours"], "is invalid")],
          errors: [operating_hours: {"is invalid", []}]
        )

      plan = Projector.project(scalar_definition(), form)

      assert [%RenderNode.Field{show_errors?: true, errors: [{"is invalid", []}]}] =
               plan.root.children

      assert [%{label: "Operating hours", message: "is invalid"}] = plan.summary
    end

    test "adapter order is preserved and multiple issues at one path stay distinct" do
      issues = [issue(["b"], "second"), issue([], "first"), issue([], "third")]

      plan = Projector.project(scalar_definition(), summary_form(issues))

      assert Enum.map(plan.summary, & &1.message) == ["second", "first", "third"]
    end

    test "scalar entries precede normalized non-field entries" do
      form =
        summary_form([issue([], "root problem")],
          errors: [operating_hours: {"is invalid", []}]
        )

      plan = Projector.project(scalar_definition(), form)

      assert [
               %{label: "Operating hours", message: "is invalid"},
               %{id: nil, label: nil, message: "root problem"}
             ] = plan.summary
    end

    # The rest of this file matches summary entries with plain map patterns,
    # which a bare map satisfies just as well as the struct. This is the one
    # assertion that pins the type itself, and it covers both entry sources
    # in one plan: a field entry and a normalized non-field entry.
    test "entries of both kinds are SummaryEntry structs" do
      form =
        summary_form([issue([], "root problem")],
          errors: [operating_hours: {"is invalid", []}]
        )

      plan = Projector.project(scalar_definition(), form)

      assert [%RenderPlan.SummaryEntry{}, %RenderPlan.SummaryEntry{}] = plan.summary
    end

    test "a :hide answer omits a non-field issue from a submitted summary" do
      form =
        summary_form([issue(["b"], "hidden problem")], visibility: %{["b"] => :hide})

      plan = Projector.project(scalar_definition(), form)

      assert plan.summary == []
    end

    test "an unavailable enumeration yields scalar entries only" do
      form =
        summary_form([], issues: :unavailable, errors: [operating_hours: {"is invalid", []}])

      plan = Projector.project(scalar_definition(), form)

      assert [%{label: "Operating hours", message: "is invalid"}] = plan.summary
    end

    # Spec §7.2: the whole point of the contract — two sources sharing no
    # internals, and disagreeing about which atom means "submitted", must
    # produce identical projector-owned decisions once their state-view
    # answers agree. Root/object issue association is covered separately:
    # by the root-issue test above for the fixture, and by the D-026
    # regression in projector_test for %Formentation.Form{}.
    test "equivalent state-view answers produce equivalent projector decisions" do
      definition = scalar_definition()

      formentation_plan =
        definition
        |> Form.new()
        |> Form.transition(%Formentation.Params{
          values: %{"operating_hours" => "51o2"},
          event: :submit
        })
        |> then(&Projector.project(definition, FormData.to_form(&1, as: "payload")))

      # Whatever decode message Formentation produced, hand the same one to
      # a source that calls its submit state :commit and enumerates nothing.
      [%{message: decode_message}] = formentation_plan.summary

      mirrored_plan =
        Projector.project(
          definition,
          summary_form([], errors: [operating_hours: {decode_message, []}])
        )

      assert decisions(mirrored_plan) == decisions(formentation_plan)
      assert decisions(formentation_plan).show_errors? == [true]
    end

    defp decisions(%RenderPlan{root: root, summary: summary}) do
      %{
        show_errors?: root |> flatten_fields() |> Enum.map(& &1.show_errors?),
        summary: Enum.map(summary, &{&1.label, &1.message})
      }
    end
  end

  # D-028's end of the wiring. The projector knows nothing about blockers —
  # these assert only the normalized outcome a blocker produces once
  # Formentation.Form's state view has translated it, which is the same
  # shape any other source's issues/2 could produce.
  describe "submission blockers reach the summary through the state view" do
    defp blocked_plan(schema, data, params) do
      {:ok, definition, _diagnostics} =
        Formentation.compile(schema, adapter: Formentation.JSONSchema)

      form_state = definition |> Form.new(data) |> submitted_form(params)
      Projector.project(definition, FormData.to_form(form_state, as: "payload"))
    end

    test "a required unsupported property is explained once, labelled, and unlinked" do
      # `oneOf` compiles to a preserve-only Unsupported node, so `required`
      # lands on ["address"]. The single-element match is the assertion that
      # matters: the bare generic "required" line must not appear beside it.
      plan =
        blocked_plan(
          %{
            "type" => "object",
            "required" => ["address"],
            "properties" => %{
              "address" => %{"oneOf" => [%{"type" => "string"}, %{"type" => "object"}]}
            }
          },
          %{},
          %{}
        )

      assert [%{id: nil, label: "Address", message: message}] = plan.summary
      assert message =~ "unsupported"
    end

    test "an editable field's error keeps its link alongside a blocker's entry" do
      plan =
        blocked_plan(
          %{
            "type" => "object",
            "required" => ["tags"],
            "properties" => %{
              "name" => %{"type" => "string", "minLength" => 3},
              "tags" => %{"type" => "array", "items" => %{"type" => "integer"}}
            }
          },
          %{},
          %{"name" => "x"}
        )

      assert [
               %{id: name_id, label: "Name"},
               %{id: nil, label: "Tags", message: message}
             ] = plan.summary

      assert name_id != nil
      assert message =~ "unsupported"
    end

    test "on change the summary stays empty even though the form is already blocked" do
      schema = %{
        "type" => "object",
        "required" => ["tags"],
        "properties" => %{"tags" => %{"type" => "array", "items" => %{"type" => "integer"}}}
      }

      {:ok, definition, _diagnostics} =
        Formentation.compile(schema, adapter: Formentation.JSONSchema)

      form_state = Form.validate(Form.new(definition), %{})

      assert {:blocked, [_]} = Form.submission_status(form_state)

      assert Projector.project(definition, FormData.to_form(form_state, as: "payload")).summary ==
               []
    end
  end

  describe "nested paths reach the state view" do
    test "a used, invalid nested field is visible on :change via the state view, not action" do
      # Discriminates against a projector that computes the wrong path for
      # a data-nesting group: Form.show_issues?/2 on :change only answers
      # true when Info.node_at(definition, segments) resolves to the
      # Semantic.Field AND its usage is :used. A path missing "address", in
      # the wrong order, or omitting the group name entirely would miss
      # the node and make this assertion fail.
      #
      # Uses the JSON Schema adapter, not Source.Map: the map adapter has
      # no schema validator, so a minLength constraint would never fire —
      # only decode failures surface issues there (see the file's earlier
      # comment on `flat_definition`/`decode_error_form`).
      schema = %{
        "type" => "object",
        "properties" => %{
          "address" => %{
            "type" => "object",
            "properties" => %{"street" => %{"type" => "string", "minLength" => 4}}
          }
        }
      }

      {:ok, definition, []} = Formentation.compile(schema, adapter: Formentation.JSONSchema)

      form_state =
        Form.transition(Form.new(definition), %Formentation.Params{
          values: %{"address" => %{"street" => "ab"}},
          event: :change
        })

      form = FormData.to_form(form_state, as: "payload")
      plan = Projector.project(definition, form)

      [address] = plan.root.children
      [street] = address.children

      assert street.errors != []
      assert street.show_errors? == true
    end
  end

  describe "absolute instance paths" do
    defp nested_path_definition do
      compile!(%{
        kind: :object,
        properties: [
          {"title", %{kind: :string}},
          {"address",
           %{
             kind: :object,
             properties: [
               {"street", %{kind: :string}},
               {"geo", %{kind: :object, properties: [{"lat", %{kind: :number}}]}}
             ]
           }}
        ]
      })
    end

    test "a data-nesting group contributes its name to a child's path" do
      definition = nested_path_definition()

      form_state =
        Form.transition(Form.new(definition), %Formentation.Params{
          values: %{"title" => "t", "address" => %{"street" => "", "geo" => %{"lat" => "x"}}},
          event: :submit
        })

      form = FormData.to_form(form_state, as: "payload")

      # ["address", "geo", "lat"] is a decode failure; hiding exactly that
      # path proves the projector reached it with its absolute segments.
      plan = Projector.project(definition, form)
      [_title, address] = plan.root.children
      [_street, geo] = address.children
      [lat] = geo.children

      assert lat.field.name == "payload[address][geo][lat]"
      assert lat.errors != []
      assert lat.show_errors?
    end

    test "a presentational group leaves the data path untouched" do
      definition =
        compile!(%{
          kind: :object,
          properties: [{"title", %{kind: :string, min_length: 4}}],
          groups: [%{id: "panel", fields: ["title"]}]
        })

      form_state =
        Form.transition(Form.new(definition), %Formentation.Params{
          values: %{"title" => "ab"},
          event: :submit
        })

      plan = Projector.project(definition, FormData.to_form(form_state, as: "payload"))

      # Whatever the group nesting looks like, the field's Phoenix name —
      # which mirrors the data path — must not gain the group id.
      names =
        plan.root
        |> flatten_fields()
        |> Enum.map(& &1.field.name)

      assert names == ["payload[title]"]
    end

    defp flatten_fields(%RenderNode.Group{children: children}),
      do: Enum.flat_map(children, &flatten_fields/1)

    defp flatten_fields(%RenderNode.Field{} = field), do: [field]
  end

  describe "architectural boundary" do
    # `.reach.exs` permits phoenix -> core, so no layer rule can express
    # "the projector knows nothing concrete about Formentation.Form".
    # A source-text assertion states that obligation directly, and is the
    # regression PR #13 must keep green when it rebases its blocker work
    # into the Formentation.Form state view.
    @projector_source File.read!("lib/formentation/phoenix/render_preparation.ex")
    # File.read!/1 above is not a Mix compile dependency by itself; it
    # currently recompiles correctly only incidentally, via the
    # `doctest Formentation.Phoenix.RenderPreparation` at the top of this file.
    # This makes the recompilation guarantee explicit rather than
    # incidental, so the pin can never validate a stale snapshot.
    @external_resource "lib/formentation/phoenix/render_preparation.ex"

    # #28 requires one authoritative decoder of the private projection key.
    # Reach cannot express "no module but these two mentions this atom" — it
    # is a literal, not a call — so a source-text pin states it directly.
    @projection_key_readers ["lib/formentation/phoenix/projected_form.ex"]
    @external_resource "lib/formentation/phoenix/projected_form.ex"

    test "only ProjectedForm spells the private projection key" do
      offenders =
        "lib/**/*.ex"
        |> Path.wildcard()
        |> Enum.filter(&(File.read!(&1) =~ ":__formentation__"))
        |> Enum.reject(&(&1 in @projection_key_readers))

      assert offenders == []
    end

    test "the projection decoder never reaches for runtime state" do
      source = File.read!("lib/formentation/phoenix/projected_form.ex")

      # Call shapes, not vocabulary: the point is that ProjectedForm decodes
      # projection metadata and never asks the source a state-dependent
      # question. A comment mentioning issues or submission must not fail
      # this — only a call to StateView can. The capitalised, word-bounded
      # pattern below additionally guards against ProjectedForm reaching for
      # a concrete %Formentation.Issue{} struct, without tripping on the
      # lowercase prose "issue"/"issues" that Task 5 deliberately allows.
      refute source =~ ~r/\bStateView\b/
      refute source =~ ~r/\bsubmitted\?\(/
      refute source =~ ~r/\bissue_visibility\(/
      refute source =~ ~r/\bissues\(/
      refute source =~ ~r/\bIssue\b/
    end

    test "the projector names no concrete runtime-state struct" do
      refute @projector_source =~ "Formentation.Form"
      refute @projector_source =~ "%Form{"
      refute @projector_source =~ "SubmissionBlocker"
    end

    test "the projector never interprets the Phoenix action itself" do
      refute @projector_source =~ "form.action"
      refute @projector_source =~ "action: :submit"
    end

    test "the projector does not discover presentation from mixed storage" do
      refute @projector_source =~ "Info.root("
      refute @projector_source =~ ~r/\bdefinition\.root\b|%Definition\{root:/
      refute @projector_source =~ "nests_data?"
      refute @projector_source =~ "%Node.Group"
    end

    test "the preparation context validates the projection root without building it" do
      # Building the root descriptor is recursive and only prepare/2 consumes it.
      # Putting it in the context made every prepare_at/3 call — that is, every
      # field/1 render — materialize the whole presentation tree to answer a
      # question about one node. A wall-clock assertion would be flaky, so pin
      # the seam instead, in the idiom this block already uses.
      assert @projector_source =~ "defp context(", "expected defp context/5 in the source"
      [_head, after_head] = String.split(@projector_source, "defp context(", parts: 2)
      [context_body, _rest] = String.split(after_head, "\n  end\n", parts: 2)

      assert context_body =~ "validate_projection_root!"
      refute context_body =~ "presentation_root_at"

      # The claim above is narrower than it looks: it only pins that
      # context/5's own body doesn't call presentation_root_at/2. Someone
      # could move the eager build one level down, into
      # validate_projection_root!/2 (still called from context/5), and
      # reinstate the exact performance regression with the assertions
      # above still green. Pin the real claim instead: presentation_root_at
      # is called only from prepare/2. It appears three times in the source
      # by construction — its two `defp` clause heads plus exactly one call
      # site — and that one call site must be inside prepare/2's body.
      prepare_marker =
        "def prepare(%Phoenix.HTML.Form{} = form, opts) when is_list(opts) do"

      assert @projector_source =~ prepare_marker, "expected prepare/2 in the source"

      [_before_prepare, after_prepare_head] =
        String.split(@projector_source, prepare_marker, parts: 2)

      [prepare_body, _rest] = String.split(after_prepare_head, "\n  end\n", parts: 2)

      assert prepare_body =~ "presentation_root_at"

      occurrences =
        @projector_source
        |> String.split("presentation_root_at(")
        |> length()
        |> Kernel.-(1)

      assert occurrences == 3
    end
  end

  describe "projection contract regressions" do
    test "project_at/3 descends from the root form for a nested scalar" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "address" => %{
            "type" => "object",
            "properties" => %{"street" => %{"type" => "string", "minLength" => 4}}
          }
        }
      }

      {:ok, definition, []} = Formentation.compile(schema, adapter: Formentation.JSONSchema)

      form_state =
        Form.transition(
          Form.new(definition, %{"address" => %{"street" => "Elm"}}),
          %Formentation.Params{
            values: %{"address" => %{"street" => "ab"}},
            event: :change
          }
        )

      form = FormData.to_form(form_state, as: "payload", id: "payload")

      from_whole =
        Projector.project(definition, form).root
        |> flatten_fields()
        |> Enum.find(&(&1.field.name == "payload[address][street]"))

      from_at = Projector.project_at(definition, form, ["address", "street"])

      assert from_at.field.name == "payload[address][street]"
      assert from_at.field.id == "payload_address_street"
      assert from_at.field.value == "ab"
      assert from_at.dom == from_whole.dom
      assert from_at.errors == from_whole.errors
      assert from_at.show_errors? == from_whole.show_errors?
      assert from_at.show_errors? == true
    end

    test "project_at/3 applies visibility using the same absolute path as project/2" do
      # :change, not :submit: Form.show_issues?/2 short-circuits to true on
      # :submit regardless of path, so that event can't discriminate a
      # context built with the wrong (non-absolute) path — see "nested
      # paths reach the state view" above for the same technique. On
      # :change, visibility depends on Info.node_at(definition, segments)
      # resolving to this exact Semantic.Field with :used usage; a project_at/3
      # that dropped the parent segments from its path would land on an
      # unknown path and answer :hide instead.
      definition = nested_path_definition()

      form_state =
        Form.transition(Form.new(definition), %Formentation.Params{
          values: %{"address" => %{"geo" => %{"lat" => "x"}}},
          event: :change
        })

      form = FormData.to_form(form_state, as: "payload")

      from_whole =
        Projector.project(definition, form).root
        |> flatten_fields()
        |> Enum.find(&(&1.field.name == "payload[address][geo][lat]"))

      from_at = Projector.project_at(definition, form, ["address", "geo", "lat"])

      assert from_at.show_errors? == from_whole.show_errors?
      assert from_at.show_errors? == true
      assert from_at.errors == from_whole.errors
    end

    test "project_at/3 raises for an unknown path" do
      definition = nested_path_definition()
      form = FormData.to_form(Form.new(definition), as: "payload")

      assert_raise ArgumentError, ~r/no node at instance path/, fn ->
        Projector.project_at(definition, form, ["nope"])
      end
    end
  end
end
