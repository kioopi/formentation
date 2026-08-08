defmodule Formentation.LayoutInvarianceTest do
  use ExUnit.Case, async: true

  import Formentation.Test.FormHelpers

  alias Formentation.{Form, Info, Issue}
  alias Formentation.Form.SubmissionBlocker

  @field_paths [
    ["title"],
    ["quantity"],
    ["revision"],
    ["details", "label"],
    ["details", "width"],
    ["details", "sku"]
  ]

  @usage_paths [
    [],
    ["details"] | @field_paths
  ]

  @issue_paths [
    [],
    ["details"],
    ["details", "attachment"] | @field_paths
  ]

  setup_all do
    {:ok, definitions: definitions()}
  end

  describe "transition semantics" do
    test "successful transition is invariant under layout", %{definitions: definitions} do
      original = %{
        "revision" => 4,
        "legacy_root" => "keep-root",
        "details" => %{
          "sku" => "RO-1",
          "attachment" => ["a.png"],
          "legacy_nested" => "keep-nested"
        }
      }

      params = %{
        "title" => "Pump",
        "quantity" => "7",
        "revision" => "99",
        "details" => %{
          "label" => "",
          "_unused_label" => "",
          "width" => "12",
          "sku" => "TAMPERED",
          "attachment" => ["b.png"]
        }
      }

      summary =
        assert_layout_invariant(definitions, fn definition ->
          definition
          |> Form.new(original)
          |> submitted_form(params)
        end)

      assert summary.candidate ==
               {:ok,
                %{
                  "title" => "Pump",
                  "quantity" => 7,
                  "revision" => 4,
                  "legacy_root" => "keep-root",
                  "details" => %{
                    "label" => "",
                    "width" => 12,
                    "sku" => "RO-1",
                    "attachment" => ["a.png"],
                    "legacy_nested" => "keep-nested"
                  }
                }}

      assert summary.submission_status == :ready
      assert summary.submission_blockers == []
      assert summary.submitted?

      assert summary.fields[["title"]].operation == {:set, "Pump"}
      assert summary.fields[["quantity"]].operation == {:set, 7}
      assert summary.fields[["details", "width"]].operation == {:set, 12}
      assert summary.fields[["details", "label"]].operation == {:set, ""}

      assert summary.fields[["revision"]].transport == {:provided, "99"}
      assert summary.fields[["revision"]].operation == :keep
      assert summary.fields[["revision"]].display_value == "4"

      assert summary.fields[["details", "sku"]].transport == {:provided, "TAMPERED"}
      assert summary.fields[["details", "sku"]].operation == :keep
      assert summary.fields[["details", "sku"]].display_value == "RO-1"

      assert summary.usage[["details", "label"]] == :unused
      assert summary.usage[["details", "width"]] == :used
      assert summary.usage[["details"]] == :used
    end

    test "undecodable transition is invariant under layout", %{definitions: definitions} do
      summary =
        assert_layout_invariant(definitions, fn definition ->
          definition
          |> Form.new()
          |> submitted_form(%{"quantity" => "3x"})
        end)

      assert summary.fields[["quantity"]].transport == {:provided, "3x"}

      assert {:invalid, %Issue{code: :invalid_integer, source: :decode}} =
               summary.fields[["quantity"]].operation

      assert summary.fields[["quantity"]].display_value == "3x"
      assert [%Issue{code: :invalid_integer, source: :decode}] = summary.issues[["quantity"]]
      assert summary.candidate == :none
      assert summary.submission_status == :undecodable
      assert summary.submission_blockers == []
    end
  end

  describe "nested content-derived presence" do
    test "absent content does not create an object", %{definitions: definitions} do
      summary =
        assert_layout_invariant(definitions, fn definition ->
          definition
          |> Form.new()
          |> submitted_form(%{})
        end)

      assert {:ok, candidate} = summary.candidate
      refute Map.has_key?(candidate, "details")
      assert summary.submission_status == :ready
      assert summary.submission_blockers == []
    end

    test "cleared content does not keep an object", %{definitions: definitions} do
      summary =
        assert_layout_invariant(definitions, fn definition ->
          definition
          |> Form.new(%{"details" => %{"width" => 4}})
          |> submitted_form(%{"details" => %{"width" => ""}})
        end)

      assert {:ok, candidate} = summary.candidate
      refute Map.has_key?(candidate, "details")
      assert summary.fields[["details", "width"]].operation == :unset
      assert summary.submission_status == :ready
      assert summary.submission_blockers == []
    end

    test "declared content creates the object", %{definitions: definitions} do
      summary =
        assert_layout_invariant(definitions, fn definition ->
          definition
          |> Form.new()
          |> submitted_form(%{"details" => %{"width" => "4"}})
        end)

      assert summary.candidate == {:ok, %{"details" => %{"width" => 4}}}

      assert [
               %SubmissionBlocker{
                 code: :unsupported_required,
                 path: %{segments: ["details", "attachment"]}
               }
             ] = summary.submission_blockers

      assert {:blocked, [_]} = summary.submission_status
    end

    test "unknown original content keeps the object present", %{definitions: definitions} do
      summary =
        assert_layout_invariant(definitions, fn definition ->
          definition
          |> Form.new(%{"details" => %{"legacy_nested" => "keep-nested"}})
          |> submitted_form(%{})
        end)

      assert summary.candidate == {:ok, %{"details" => %{"legacy_nested" => "keep-nested"}}}

      assert [
               %SubmissionBlocker{
                 code: :unsupported_required,
                 path: %{segments: ["details", "attachment"]}
               }
             ] = summary.submission_blockers

      assert {:blocked, [_]} = summary.submission_status
    end

    test "unsupported original content keeps the object present", %{definitions: definitions} do
      summary =
        assert_layout_invariant(definitions, fn definition ->
          definition
          |> Form.new(%{"details" => %{"attachment" => ["a.png"]}})
          |> submitted_form(%{})
        end)

      assert summary.candidate == {:ok, %{"details" => %{"attachment" => ["a.png"]}}}
      assert summary.submission_status == :ready
      assert summary.submission_blockers == []
    end
  end

  test "presentation group IDs never become instance-path segments", %{definitions: definitions} do
    regrouped = definitions.regrouped

    assert Info.node_at(regrouped, ["details", "width"])
    assert Info.node_at(regrouped, ["main", "details", "width"]) == nil
    assert Info.node_at(regrouped, ["details", "technical", "width"]) == nil
  end

  defp assert_layout_invariant(definitions, transition_fun) do
    plain = definitions.plain |> transition_fun.() |> observable_summary()
    regrouped = definitions.regrouped |> transition_fun.() |> observable_summary()

    assert regrouped == plain
    plain
  end

  defp observable_summary(form) do
    %{
      candidate: Form.candidate(form),
      submitted?: Form.submitted?(form),
      submission_status: Form.submission_status(form),
      submission_blockers: Form.submission_blockers(form),
      fields: field_summaries(form),
      issues: path_entries(@issue_paths, &Form.issues(form, &1)),
      usage: path_entries(@usage_paths, &Form.usage(form, &1))
    }
  end

  defp field_summaries(form) do
    path_entries(@field_paths, fn path ->
      field = Form.field(form, path)

      %{
        transport: field.transport,
        operation: field.operation,
        usage: field.usage,
        issues: field.issues,
        display_value: field.display_value
      }
    end)
  end

  defp path_entries(paths, fun) do
    Map.new(paths, fn path -> {path, fun.(path)} end)
  end

  defp definitions do
    %{
      plain: compile_definition([], []),
      regrouped:
        compile_definition(
          [%{id: "main", title: "Main", fields: ["details", "quantity", "title"]}],
          [
            %{
              id: "technical",
              title: "Technical",
              fields: ["attachment", "sku", "width", "label"]
            }
          ]
        )
    }
  end

  defp compile_definition(root_groups, details_groups) do
    {:ok, definition, diagnostics} =
      root_groups
      |> declaration(details_groups)
      |> Formentation.compile(adapter: Formentation.Source.Map)

    assert Enum.map(diagnostics, & &1.code) == [:unsupported_kind]

    definition
  end

  defp declaration(root_groups, details_groups) do
    details = %{
      kind: :object,
      required: ["attachment"],
      properties: [
        {"label", %{kind: :string}},
        {"width", %{kind: :integer}},
        {"sku", %{kind: :string, read_only: true}},
        {"attachment", %{kind: :file}}
      ],
      groups: details_groups
    }

    %{
      kind: :object,
      properties: [
        {"title", %{kind: :string}},
        {"quantity", %{kind: :integer}},
        {"revision", %{kind: :integer, read_only: true}},
        {"details", details}
      ],
      groups: root_groups
    }
  end
end
