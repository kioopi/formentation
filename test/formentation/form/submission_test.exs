defmodule Formentation.Form.SubmissionTest do
  use ExUnit.Case, async: true

  alias Formentation.Form.{Submission, SubmissionBlocker}
  alias Formentation.{InstancePath, Issue}

  doctest Formentation.Form.Submission

  defp definition(source) do
    {:ok, definition, _diagnostics} =
      Formentation.compile(source, adapter: Formentation.Source.Map)

    definition
  end

  test "a required preserve-only value absent from the candidate blocks" do
    definition =
      definition(%{
        kind: :object,
        required: ["attachment"],
        properties: [{"attachment", %{kind: :file}}]
      })

    assert [%SubmissionBlocker{code: :unsupported_required, issues: []} = blocker] =
             Submission.blockers(definition, %{}, %{})

    assert blocker.path == InstancePath.new!(["attachment"])
  end

  test "a required preserve-only value present in the candidate does not block" do
    definition =
      definition(%{
        kind: :object,
        required: ["attachment"],
        properties: [{"attachment", %{kind: :file}}]
      })

    assert Submission.blockers(definition, %{"attachment" => "scan.pdf"}, %{}) == []
  end

  test "validation issues at an optional preserve-only path block as unsupported_invalid" do
    definition =
      definition(%{kind: :object, properties: [{"attachment", %{kind: :file}}]})

    path = InstancePath.new!(["attachment"])

    issue = %Issue{path: path, code: :format, message: "bad format", source: :validation}

    assert [%SubmissionBlocker{code: :unsupported_invalid, issues: [^issue]}] =
             Submission.blockers(
               definition,
               %{"attachment" => "scan.pdf"},
               %{path => [issue]}
             )
  end
end
