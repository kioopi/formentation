defmodule Formentation.FormSubmissionTest do
  use ExUnit.Case, async: true

  import Formentation.Test.FormHelpers

  alias Formentation.{
    Form,
    InstancePath,
    Issue,
    SubmissionBlocker,
    TemplatePath,
    ValidationPlan
  }

  alias Formentation.Definition.{Finalizer, Presentation, Semantic}

  # ---- JSON Schema fixture: `tags` is an unsupported array whose items the
  # full schema still validates; `title` is an unrelated editable sibling.
  defp tags_schema(opts) do
    tags_required = Keyword.get(opts, :tags_required, false)

    schema = %{
      "type" => "object",
      "required" => if(tags_required, do: ["tags"], else: []),
      "properties" => %{
        "title" => %{"type" => "string"},
        "tags" => %{"type" => "array", "items" => %{"type" => "integer"}}
      }
    }

    {:ok, definition, _diagnostics} =
      Formentation.compile(schema, adapter: Formentation.JSONSchema)

    definition
  end

  defp submit(definition, original, params \\ %{}) do
    definition
    |> Form.new(original)
    |> submitted_form(params)
  end

  describe "JSON Schema runtime matrix" do
    test "optional + absent -> :ready, no blockers" do
      assert {:ok, _candidate, _form} =
               Form.submit(Form.new(tags_schema(tags_required: false), %{"title" => "t"}), %{})

      form = submit(tags_schema(tags_required: false), %{"title" => "t"})
      assert Form.submission_blockers(form) == []
      assert Form.submission_status(form) == :ready
    end

    test "optional + present valid -> :ready, value preserved" do
      form = submit(tags_schema(tags_required: false), %{"tags" => [1, 2]})
      assert Form.submission_blockers(form) == []
      assert Form.submission_status(form) == :ready
      assert {:ok, %{"tags" => [1, 2]}} = Form.candidate(form)
    end

    test "optional + present invalid -> :unsupported_invalid, {:blocked}" do
      form = submit(tags_schema(tags_required: false), %{"tags" => ["x"]})

      assert [%SubmissionBlocker{code: :unsupported_invalid, node_id: node_id} = blocker] =
               Form.submission_blockers(form)

      assert blocker.path == InstancePath.new!(["tags"])
      assert node_id =~ "tags"
      assert blocker.issues != []
      assert {:blocked, [^blocker]} = Form.submission_status(form)
      # invalid original value is still preserved, not pruned
      assert {:ok, %{"tags" => ["x"]}} = Form.candidate(form)
    end

    test "required + absent -> :unsupported_required, {:blocked}" do
      form = submit(tags_schema(tags_required: true), %{"title" => "t"})

      assert [%SubmissionBlocker{code: :unsupported_required} = blocker] =
               Form.submission_blockers(form)

      assert blocker.path == InstancePath.new!(["tags"])
      assert {:blocked, [_]} = Form.submission_status(form)
      assert {:ok, candidate} = Form.candidate(form)
      refute Map.has_key?(candidate, "tags")
    end

    test "required + present valid -> :ready" do
      assert {:ok, _candidate, form} =
               Form.submit(Form.new(tags_schema(tags_required: true), %{"tags" => [1]}), %{})

      assert Form.submission_blockers(form) == []
      assert Form.submission_status(form) == :ready
    end

    test "required + present invalid -> :unsupported_invalid, {:blocked}" do
      form = submit(tags_schema(tags_required: true), %{"tags" => ["x"]})
      assert [%SubmissionBlocker{code: :unsupported_invalid}] = Form.submission_blockers(form)
      assert {:blocked, [_]} = Form.submission_status(form)
    end

    test "submitted params can neither supply nor replace the unsupported value" do
      # required + absent: a submitted value for `tags` is ignored, stays blocked
      form = submit(tags_schema(tags_required: true), %{}, %{"tags" => "[1,2,3]"})
      assert {:ok, candidate} = Form.candidate(form)
      refute Map.has_key?(candidate, "tags")
      assert [%SubmissionBlocker{code: :unsupported_required}] = Form.submission_blockers(form)

      # present valid: a submitted replacement is ignored, original survives
      kept = submit(tags_schema(tags_required: false), %{"tags" => [1, 2]}, %{"tags" => "[9]"})
      assert {:ok, %{"tags" => [1, 2]}} = Form.candidate(kept)
    end
  end

  describe "descendant issue ownership" do
    test "a validation issue below the unsupported path is owned by that node" do
      form = submit(tags_schema(tags_required: false), %{"tags" => ["x"]})

      assert [%SubmissionBlocker{path: path, issues: [_ | _] = issues}] =
               Form.submission_blockers(form)

      assert path == InstancePath.new!(["tags"])

      # every owned issue is at or below ["tags"] and came from validation
      assert Enum.all?(issues, fn issue ->
               issue.source == :validation and
                 InstancePath.ancestor_or_self?(path, issue.path)
             end)
    end
  end

  # ---- Hand-built definition + fake validator: full control over issue paths.
  defmodule FakeValidation do
    @behaviour Formentation.Validation
    @impl true
    # artifact IS the fixed issue list, ignoring the instance
    def validate(issues, _instance), do: issues
  end

  defp fake_definition(opts) do
    tags_required = Keyword.get(opts, :tags_required, false)
    issues = Keyword.get(opts, :issues, [])

    semantic =
      Semantic.Object.new(nil, %TemplatePath{segments: []}, [
        Semantic.Field.new("name", %TemplatePath{segments: ["name"]}, :string, role: :text),
        Semantic.Unsupported.new("tags", %TemplatePath{segments: ["tags"]},
          required?: tags_required
        )
      ])

    presentation = Presentation.Object.new("/", [Presentation.Field.new("/name")])

    {:ok, definition} = Finalizer.finalize(semantic, presentation)
    %{definition | validation: %ValidationPlan{module: FakeValidation, artifact: issues}}
  end

  defp issue(segments, code, source \\ :validation) do
    %Issue{
      path: InstancePath.new!(segments),
      code: code,
      message: "#{code} at #{inspect(segments)}",
      source: source
    }
  end

  describe "submit/2 decision" do
    test "ready returns the decoded candidate and submitted form" do
      definition = compile_map(%{kind: :object, properties: [{"age", %{kind: :integer}}]})
      original = %{"old" => "kept"}
      params = %{"age" => "42"}

      assert {:ok, %{"old" => "kept", "age" => 42} = candidate, submitted_form} =
               Form.submit(Form.new(definition, original), params)

      assert Form.candidate(submitted_form) == {:ok, candidate}
      assert Form.submission_status(submitted_form) == :ready
      assert submitted_form.action == :submit
      assert Form.submitted?(submitted_form)
      assert original == %{"old" => "kept"}
      assert params == %{"age" => "42"}
    end

    test "undecodable returns the submitted form for redisplay" do
      definition = compile_map(%{kind: :object, properties: [{"age", %{kind: :integer}}]})

      assert {:error, submitted_form} =
               Form.submit(Form.new(definition), %{"age" => "not-a-number"})

      assert Form.candidate(submitted_form) == :none
      assert Form.submission_status(submitted_form) == :undecodable
      assert Form.submission_blockers(submitted_form) == []
      assert submitted_form.action == :submit
      assert Form.submitted?(submitted_form)
      assert Form.show_issues?(submitted_form, ["age"])

      assert [
               %Issue{
                 path: %InstancePath{segments: ["age"]},
                 code: :invalid_integer,
                 source: :decode
               }
             ] = Form.issues(submitted_form, ["age"])

      assert Form.field(submitted_form, ["age"]).display_value == "not-a-number"
      assert Form.usage(submitted_form, ["age"]) == :used
    end

    test "blocked required unsupported map source returns error despite candidate and no ordinary issues" do
      definition =
        compile_map(%{
          kind: :object,
          required: ["attachment"],
          properties: [
            {"title", %{kind: :string}},
            {"attachment", %{kind: :file}}
          ]
        })

      assert {:error, submitted_form} =
               Form.submit(Form.new(definition), %{"title" => "Inspection"})

      assert {:ok, %{"title" => "Inspection"}} = Form.candidate(submitted_form)
      assert Form.issues(submitted_form) == []
      assert submitted_form.action == :submit
      assert Form.submitted?(submitted_form)

      assert {:blocked,
              [
                %SubmissionBlocker{
                  code: :unsupported_required,
                  path: %InstancePath{segments: ["attachment"]},
                  issues: []
                }
              ]} = Form.submission_status(submitted_form)
    end

    test "invalid returns the submitted form while preserving decoded candidate and validation issue" do
      schema = %{
        "type" => "object",
        "properties" => %{"title" => %{"type" => "string", "minLength" => 3}}
      }

      {:ok, definition, _diagnostics} =
        Formentation.compile(schema, adapter: Formentation.JSONSchema)

      assert {:error, submitted_form} = Form.submit(Form.new(definition), %{"title" => "No"})

      assert {:ok, %{"title" => "No"}} = Form.candidate(submitted_form)
      assert Form.field(submitted_form, ["title"]).display_value == "No"
      assert submitted_form.action == :submit
      assert Form.submitted?(submitted_form)
      assert Form.show_issues?(submitted_form, ["title"])

      assert {:invalid,
              [
                %Issue{
                  path: %InstancePath{segments: ["title"]},
                  code: :minLength,
                  source: :validation
                }
              ]} = Form.submission_status(submitted_form)
    end

    test "validate and transition still expose low-level form transitions" do
      definition = compile_map(%{kind: :object, properties: [{"title", %{kind: :string}}]})
      form = Form.new(definition)

      changed = Form.validate(form, %{"title" => "Draft"})

      transitioned =
        Form.transition(form, %Formentation.Params{values: %{"title" => "Done"}, event: :submit})

      assert %Form{action: :change} = changed
      assert %Form{action: :submit} = transitioned

      assert {:ok, %{"title" => "Done"}, %Form{action: :submit}} =
               Form.submit(form, %{"title" => "Done"})
    end
  end

  describe "status precedence and mixed issues" do
    test "clean candidate -> :ready" do
      form = Form.new(fake_definition(issues: []), %{"name" => "ok"})
      assert Form.submission_status(form) == :ready
    end

    test "an ordinary editable-field issue with no blocker -> {:invalid, issues}" do
      form = Form.new(fake_definition(issues: [issue(["name"], :too_short)]), %{"name" => "x"})
      assert Form.submission_blockers(form) == []
      assert {:invalid, [%Issue{code: :too_short}]} = Form.submission_status(form)
    end

    test "a blocker plus an editable-field issue -> {:blocked}, but issues/1 returns both" do
      form =
        Form.new(
          fake_definition(tags_required: true, issues: [issue(["name"], :too_short)]),
          %{"name" => "x"}
        )

      assert {:blocked, [%SubmissionBlocker{code: :unsupported_required}]} =
               Form.submission_status(form)

      codes = form |> Form.issues() |> Enum.map(& &1.code) |> Enum.sort()
      assert :too_short in codes
    end

    test "multiple issues under one unsupported node collapse into one blocker" do
      form =
        Form.new(
          fake_definition(issues: [issue(["tags"], :bad_a), issue(["tags", 0], :bad_b)]),
          %{"name" => "n", "tags" => "opaque"}
        )

      assert [%SubmissionBlocker{code: :unsupported_invalid, issues: issues}] =
               Form.submission_blockers(form)

      assert [_, _] = issues
    end

    test "an authoritative issue at an absent required unsupported path still yields :unsupported_required, issue carried" do
      form =
        Form.new(
          fake_definition(tags_required: true, issues: [issue(["tags"], :required)]),
          %{"name" => "n"}
        )

      assert [%SubmissionBlocker{code: :unsupported_required, issues: [%Issue{code: :required}]}] =
               Form.submission_blockers(form)
    end
  end

  describe "causal limit" do
    test "an issue exactly at the unsupported path is blocked" do
      form =
        Form.new(fake_definition(issues: [issue(["tags"], :bad)]), %{"name" => "n", "tags" => "x"})

      assert [%SubmissionBlocker{path: p}] = Form.submission_blockers(form)
      assert p == InstancePath.new!(["tags"])
    end

    test "a root issue is not classified as an unsupported blocker" do
      form =
        Form.new(fake_definition(issues: [issue([], :root_rule)]), %{"name" => "n", "tags" => "x"})

      assert Form.submission_blockers(form) == []
      assert {:invalid, [%Issue{code: :root_rule}]} = Form.submission_status(form)
    end

    test "an editable-sibling issue stays ordinary invalidity" do
      form =
        Form.new(fake_definition(issues: [issue(["name"], :bad)]), %{"name" => "x", "tags" => "y"})

      assert Form.submission_blockers(form) == []
      assert {:invalid, [%Issue{code: :bad}]} = Form.submission_status(form)
    end
  end

  describe ":undecodable" do
    test "a decode failure yields candidate :none, status :undecodable, no blockers" do
      # integer field `age` fails to decode -> candidate :none
      {:ok, definition, _} =
        Formentation.compile(
          %{
            kind: :object,
            properties: [{"age", %{kind: :integer}}, {"attachment", %{kind: :file}}]
          },
          adapter: Formentation.Source.Map
        )

      form = definition |> Form.new(%{}) |> submitted_form(%{"age" => "not-a-number"})

      assert Form.candidate(form) == :none
      assert Form.submission_status(form) == :undecodable
      assert Form.submission_blockers(form) == []
    end
  end

  # ---- Map source: no ValidationPlan, so blockers come only from the
  # source-neutral missing-required fallback (issues: []).
  defp compile_map(declaration) do
    {:ok, definition, _diagnostics} =
      Formentation.compile(declaration, adapter: Formentation.Source.Map)

    definition
  end

  describe "validation-less source (map): missing-required fallback" do
    test "optional unsupported absent -> :ready" do
      definition = compile_map(%{kind: :object, properties: [{"attachment", %{kind: :file}}]})
      form = definition |> Form.new(%{}) |> submitted_form(%{})
      assert Form.submission_status(form) == :ready
    end

    test "required unsupported absent at root -> :unsupported_required with issues: []" do
      definition =
        compile_map(%{
          kind: :object,
          required: ["attachment"],
          properties: [{"attachment", %{kind: :file}}]
        })

      form = definition |> Form.new(%{}) |> submitted_form(%{})

      assert [%SubmissionBlocker{code: :unsupported_required, issues: []}] =
               Form.submission_blockers(form)
    end

    test "required unsupported present -> no blocker, present value never labelled invalid" do
      definition =
        compile_map(%{
          kind: :object,
          required: ["attachment"],
          properties: [{"attachment", %{kind: :file}}]
        })

      assert {:ok, _candidate, form} =
               Form.submit(Form.new(definition, %{"attachment" => ["a.png"]}), %{})

      assert Form.submission_blockers(form) == []
      assert Form.submission_status(form) == :ready
    end

    test "submitted params cannot supply or replace the value" do
      definition =
        compile_map(%{
          kind: :object,
          required: ["attachment"],
          properties: [{"attachment", %{kind: :file}}]
        })

      form = definition |> Form.new(%{}) |> submitted_form(%{"attachment" => "sneaky"})
      assert {:ok, candidate} = Form.candidate(form)
      refute Map.has_key?(candidate, "attachment")
      assert [%SubmissionBlocker{code: :unsupported_required}] = Form.submission_blockers(form)
    end
  end

  # profile.{nickname:string (editable), legacy_tags:file (unsupported, required)}
  defp profile_definition do
    compile_map(%{
      kind: :object,
      properties: [
        {"profile",
         %{
           kind: :object,
           required: ["legacy_tags"],
           properties: [
             {"nickname", %{kind: :string}},
             {"legacy_tags", %{kind: :file}}
           ]
         }}
      ]
    })
  end

  describe "nested presence integration with #1 (map source)" do
    test "an absent optional parent deactivates its required unsupported child (no blocker)" do
      form = profile_definition() |> Form.new(%{}) |> submitted_form(%{})
      assert {:ok, %{}} = Form.candidate(form)
      assert Form.submission_blockers(form) == []
      assert Form.submission_status(form) == :ready
    end

    test "a surviving editable sibling keeps the parent, activating the required child (blocker)" do
      form =
        profile_definition()
        |> Form.new(%{})
        |> submitted_form(%{"profile" => %{"nickname" => "vt"}})

      assert {:ok, %{"profile" => %{"nickname" => "vt"}}} = Form.candidate(form)

      assert [%SubmissionBlocker{code: :unsupported_required, path: path}] =
               Form.submission_blockers(form)

      assert path == InstancePath.new!(["profile", "legacy_tags"])
    end

    test "a preserved valid child keeps the parent and creates no blocker" do
      form =
        profile_definition()
        |> Form.new(%{"profile" => %{"legacy_tags" => ["a.png"]}})
        |> submitted_form(%{"profile" => %{"nickname" => "vt"}})

      assert {:ok, %{"profile" => %{"nickname" => "vt", "legacy_tags" => ["a.png"]}}} =
               Form.candidate(form)

      assert Form.submission_blockers(form) == []
    end

    test "omitting the last editable child removes the parent under #1 and deactivates the child" do
      # Replace semantics: an omitted child decodes to :unset, so the object
      # empties and #1 (D-026) drops it; the required unsupported child then
      # has no active parent and produces no blocker.
      form =
        profile_definition()
        |> Form.new(%{"profile" => %{"nickname" => "vt"}})
        |> submitted_form(%{"profile" => %{}})

      assert {:ok, candidate} = Form.candidate(form)
      refute Map.has_key?(candidate, "profile")
      assert Form.submission_blockers(form) == []
    end

    test "a blank string child survives (D-010), keeps the parent, and keeps the required child blocked" do
      # D-010: "" decodes to {:set, ""} for a string field — a surviving value —
      # so the parent object stays present and its required unsupported child
      # stays active. Removal needs omission (the test above), not a blank string.
      form =
        profile_definition()
        |> Form.new(%{"profile" => %{"nickname" => "vt"}})
        |> submitted_form(%{"profile" => %{"nickname" => ""}})

      assert {:ok, %{"profile" => %{"nickname" => ""}}} = Form.candidate(form)

      assert [%SubmissionBlocker{code: :unsupported_required, path: path}] =
               Form.submission_blockers(form)

      assert path == InstancePath.new!(["profile", "legacy_tags"])
    end
  end

  describe "trust boundary (D-009) with blockers present" do
    test "invalid preserved data survives transitions while producing a blocker" do
      definition = tags_schema(tags_required: false)

      form =
        definition
        |> Form.new(%{"tags" => ["x"], "title" => "keep"})
        |> submitted_form(%{"title" => "changed", "tags" => "ignored"})

      # original invalid unsupported value survives byte-for-byte...
      assert {:ok, %{"tags" => ["x"], "title" => "changed"}} = Form.candidate(form)
      # ...and is reported as a blocker, not silently accepted
      assert [%SubmissionBlocker{code: :unsupported_invalid}] = Form.submission_blockers(form)
    end

    test "validation receives the preserved candidate, not raw submitted opaque data" do
      # If submitted "ignored" had reached validation, an integer-array schema
      # would flag a different (string) issue; instead the preserved ["x"] is
      # what gets validated, so the blocker owns an item-level issue.
      form =
        tags_schema(tags_required: false)
        |> Form.new(%{"tags" => ["x"]})
        |> submitted_form(%{"tags" => "ignored"})

      assert {:ok, %{"tags" => ["x"]}} = Form.candidate(form)

      assert [
               %SubmissionBlocker{
                 code: :unsupported_invalid,
                 path: path,
                 issues: [_ | _] = issues
               }
             ] =
               Form.submission_blockers(form)

      # every owned issue is at or below the blocker's path and came from
      # validation of the preserved ["x"], not the submitted "ignored" string
      assert Enum.all?(issues, fn issue ->
               issue.source == :validation and
                 InstancePath.ancestor_or_self?(path, issue.path)
             end)
    end
  end
end
