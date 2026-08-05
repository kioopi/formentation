defmodule Formentation.Phoenix.RenderPreparationTest.ProjectorAdapter do
  @moduledoc false

  alias Formentation.Phoenix.RenderPreparation

  def project(definition, form), do: RenderPreparation.prepare(definition, form)

  def project(definition, form, opts), do: RenderPreparation.prepare(definition, form, opts)

  def project_at(definition, form, path), do: RenderPreparation.prepare_at(definition, form, path)

  def project_at(definition, form, path, opts),
    do: RenderPreparation.prepare_at(definition, form, path, opts)
end

defmodule Formentation.Phoenix.RenderPreparationTest do
  use ExUnit.Case, async: true

  import Formentation.Test.FormHelpers

  doctest Formentation.Phoenix.RenderPreparation

  alias Formentation.Definition.Finalizer
  alias Formentation.{Form, InstancePath, NodeId, TemplatePath}
  alias Formentation.Phoenix.{DOMIdentity, RenderNode, RenderPlan}
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

      form = FormData.to_form(Form.new(first), as: "payload")
      assert Projector.project(first, form) == Projector.project(first, form)

      identities = fn definition ->
        definition
        |> Projector.project(form)
        |> Map.fetch!(:root)
        |> flatten_fields()
        |> Map.new(&{&1.field.name, &1.dom})
      end

      assert identities.(first) == identities.(second)
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
