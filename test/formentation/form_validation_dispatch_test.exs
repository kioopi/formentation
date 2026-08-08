defmodule Formentation.FormValidationDispatchTest do
  use ExUnit.Case, async: true

  import Formentation.Test.FormHelpers

  alias Formentation.Definition.ValidationPlan
  alias Formentation.{Form, InstancePath, Issue}

  # A Validation implementation with no relationship to JSON Schema or JSV.
  # Its artifact reports invocations back to the test process and carries
  # the issues to return, proving core dispatch is source-neutral.
  defmodule Fake do
    @behaviour Formentation.Definition.Validation

    @impl true
    def validate(:boom, _instance), do: raise("boom")

    def validate(%{pid: pid, issues: issues}, instance) do
      send(pid, {:validated, instance})
      issues
    end
  end

  defp base_definition do
    {:ok, definition, []} =
      Formentation.compile(
        %{kind: :object, properties: [{"a", %{kind: :string}}, {"b", %{kind: :string}}]},
        adapter: Formentation.Source.Map
      )

    definition
  end

  defp with_plan(definition, artifact) do
    %{definition | validation: %ValidationPlan{module: Fake, artifact: artifact}}
  end

  defp issue(segment, code) do
    %Issue{
      path: InstancePath.new!([segment]),
      code: code,
      message: "#{segment} is invalid",
      source: :validation
    }
  end

  test "validation: nil produces no validation issues and never dispatches" do
    form = Form.new(base_definition(), %{"a" => "x"})
    assert Form.issues(form) == []
    refute_received {:validated, _}
  end

  test "a fake returning [] leaves the form valid" do
    definition = with_plan(base_definition(), %{pid: self(), issues: []})
    form = Form.new(definition, %{"a" => "x"})
    assert Form.issues(form) == []
  end

  test "Form.new/3 dispatches the exact stored artifact and initial candidate" do
    artifact = %{pid: self(), issues: []}
    Form.new(with_plan(base_definition(), artifact), %{"a" => "x", "b" => "y"})
    assert_receive {:validated, %{"a" => "x", "b" => "y"}}
  end

  test "transition/2 dispatches again with the newly decoded candidate" do
    definition = with_plan(base_definition(), %{pid: self(), issues: []})
    form = Form.new(definition, %{})
    assert_receive {:validated, %{}}

    Form.validate(form, %{"a" => "z"})
    assert_receive {:validated, %{"a" => "z"}}
  end

  test "multiple returned issues are preserved and grouped at their exact path" do
    issues = [issue("a", :bad_a), issue("b", :bad_b)]
    definition = with_plan(base_definition(), %{pid: self(), issues: issues})
    form = Form.new(definition, %{"a" => "x", "b" => "y"})

    assert [%Issue{code: :bad_a}] = Form.issues(form, ["a"])
    assert [%Issue{code: :bad_b}] = Form.issues(form, ["b"])
  end

  test "a decode failure sets candidate :none and does not dispatch" do
    {:ok, int_def, []} =
      Formentation.compile(
        %{kind: :object, properties: [{"age", %{kind: :integer}}]},
        adapter: Formentation.Source.Map
      )

    definition = %{
      int_def
      | validation: %ValidationPlan{module: Fake, artifact: %{pid: self(), issues: []}}
    }

    form = Form.new(definition, %{})
    assert_receive {:validated, %{}}

    broken = submitted_form(form, %{"age" => "not-an-int"})
    assert Form.candidate(broken) == :none
    refute_receive {:validated, _}
  end

  test "a callback exception propagates rather than becoming an Issue" do
    definition = with_plan(base_definition(), :boom)
    assert_raise RuntimeError, "boom", fn -> Form.new(definition, %{"a" => "x"}) end
  end
end
