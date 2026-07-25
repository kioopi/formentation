defmodule Formentation.Phoenix.StateViewTest do
  use ExUnit.Case, async: true

  doctest Formentation.Phoenix.StateView

  alias Formentation.InstancePath
  alias Formentation.Phoenix.StateView

  # A plain map is a real, non-Formentation Phoenix.HTML.FormData source
  # with no StateView implementation, so it exercises the Any fallback
  # exactly as an unadapted third-party source would.
  defp generic_form(action) do
    form = Phoenix.HTML.FormData.to_form(%{"a" => "1"}, as: "payload")
    %{form | action: action}
  end

  describe "Any fallback" do
    test "reports submitted only for the Phoenix :submit action" do
      form = generic_form(:submit)
      assert StateView.submitted?(form.source, form)
    end

    test "does not treat :commit, :save, or nil as submitted" do
      for action <- [:commit, :save, nil] do
        form = generic_form(action)
        refute StateView.submitted?(form.source, form)
      end
    end

    test "defers visibility to the projector's Phoenix default" do
      form = generic_form(:submit)

      assert StateView.issue_visibility(form.source, form, InstancePath.new!([])) == :default

      assert StateView.issue_visibility(form.source, form, InstancePath.new!(["a"])) ==
               :default
    end

    test "reports issue enumeration as unavailable rather than guessing" do
      form = generic_form(:submit)
      assert StateView.issues(form.source, form) == :unavailable
    end
  end
end
