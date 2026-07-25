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
      # `address` is a plain supported `"type": "object"`. Under D-026
      # (issue #1) a required nested object with no content stays genuinely
      # absent from the candidate, so JSV files the `:required` issue at the
      # group's own path, ["address"]. That path resolves to a Group, not a
      # Node.Field and not a Node.Unsupported, so the state view's
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

      form_state = Form.submit(Form.new(definition), %{"title" => "t"})
      plan = Projector.project(definition, FormData.to_form(form_state, []))

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

      Phoenix.HTML.FormData.to_form(source, [])
    end

    test "a source whose semantic submit is :commit reveals an unused field's error" do
      plan = Projector.project(scalar_definition(), fixture_form(submitted?: true))

      assert [%RenderNode.Field{show_errors?: true}] = plan.root.children
      assert [%{label: "Operating hours", message: "is invalid"}] = plan.summary
    end

    test "the generic fallback does not treat :commit as submitted" do
      form = %{
        Phoenix.HTML.FormData.to_form(unused_params(), [])
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

      Phoenix.HTML.FormData.to_form(source, [])
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
        |> then(&Projector.project(definition, FormData.to_form(&1, [])))

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

  describe "nested paths reach the state view" do
    test "a used, invalid nested field is visible on :change via the state view, not action" do
      # Discriminates against a projector that computes the wrong path for
      # a data-nesting group: Form.show_issues?/2 on :change only answers
      # true when Info.node_at(definition, segments) resolves to the
      # Node.Field AND its usage is :used. A path missing "address", in
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

      form = FormData.to_form(form_state, [])
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

      form = FormData.to_form(form_state, [])

      # ["address", "geo", "lat"] is a decode failure; hiding exactly that
      # path proves the projector reached it with its absolute segments.
      plan = Projector.project(definition, form)
      [_title, address] = plan.root.children
      [_street, geo] = address.children
      [lat] = geo.children

      assert lat.field.name == "address[geo][lat]"
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

      plan = Projector.project(definition, FormData.to_form(form_state, []))

      # Whatever the group nesting looks like, the field's Phoenix name —
      # which mirrors the data path — must not gain the group id.
      names =
        plan.root
        |> flatten_fields()
        |> Enum.map(& &1.field.name)

      assert names == ["title"]
    end

    defp flatten_fields(%RenderNode.Group{children: children}),
      do: Enum.flat_map(children, &flatten_fields/1)

    defp flatten_fields(%RenderNode.Field{} = field), do: [field]
  end
end
