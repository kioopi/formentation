defmodule Formentation.Phoenix.StateViewTest do
  use ExUnit.Case, async: true

  doctest Formentation.Phoenix.StateView

  alias Formentation.{Form, Params}
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

  describe "Formentation.Form state view" do
    defp address_definition do
      schema = %{
        "type" => "object",
        "required" => ["address"],
        "properties" => %{
          "title" => %{"type" => "string"},
          "address" => %{
            "type" => "object",
            "required" => ["street"],
            "properties" => %{"street" => %{"type" => "string"}}
          }
        }
      }

      {:ok, definition, _diagnostics} =
        Formentation.compile(schema, adapter: Formentation.JSONSchema)

      definition
    end

    defp form_pair(form_state) do
      {form_state, Phoenix.HTML.FormData.to_form(form_state, [])}
    end

    test "reports submitted only after a submit transition" do
      definition = address_definition()

      {pristine, pristine_form} = form_pair(Form.new(definition))
      {changed, changed_form} = form_pair(Form.validate(Form.new(definition), %{"title" => "t"}))

      {submitted, submitted_form} =
        form_pair(Form.submit(Form.new(definition), %{"title" => "t"}))

      refute StateView.submitted?(pristine, pristine_form)
      refute StateView.submitted?(changed, changed_form)
      assert StateView.submitted?(submitted, submitted_form)
    end

    test "visibility agrees with Form.show_issues?/2 for scalar, group and root paths" do
      definition = address_definition()

      states = [
        Form.new(definition),
        Form.transition(Form.new(definition), %Params{
          values: %{"title" => "t", "_unused_title" => ""},
          event: :change
        }),
        Form.transition(Form.new(definition), %Params{
          values: %{"title" => "t"},
          event: :change
        }),
        Form.submit(Form.new(definition), %{"title" => "t"})
      ]

      paths = [[], ["title"], ["address"], ["address", "street"]]

      for state <- states, segments <- paths do
        {form_state, form} = form_pair(state)
        expected = if Form.show_issues?(form_state, segments), do: :show, else: :hide

        assert StateView.issue_visibility(
                 form_state,
                 form,
                 InstancePath.new!(segments)
               ) == expected,
               "disagreed at #{inspect(segments)} for action #{inspect(form_state.action)}"
      end
    end

    test "never answers :default" do
      {form_state, form} = form_pair(Form.submit(Form.new(address_definition()), %{}))

      for segments <- [[], ["title"], ["address"]] do
        refute StateView.issue_visibility(form_state, form, InstancePath.new!(segments)) ==
                 :default
      end
    end

    test "normalizes every issue with its absolute path and message" do
      {form_state, form} = form_pair(Form.submit(Form.new(address_definition()), %{}))

      assert {:ok, issues} = StateView.issues(form_state, form)
      assert [%StateView.Issue{} | _] = issues

      paths = Enum.map(issues, & &1.path.segments)
      assert ["address"] in paths

      for %StateView.Issue{message: message} <- issues do
        assert is_binary(message) and message != ""
      end
    end

    test "orders normalized issues deterministically by path" do
      {form_state, form} = form_pair(Form.submit(Form.new(address_definition()), %{}))

      assert {:ok, issues} = StateView.issues(form_state, form)
      paths = Enum.map(issues, & &1.path.segments)

      assert paths == Enum.sort(paths)
      assert {:ok, ^issues} = StateView.issues(form_state, form)
    end

    defp code_definition do
      schema = %{
        "type" => "object",
        "properties" => %{
          "code" => %{"type" => "string", "minLength" => 5, "pattern" => "^[A-Z]+$"}
        }
      }

      {:ok, definition, _diagnostics} =
        Formentation.compile(schema, adapter: Formentation.JSONSchema)

      definition
    end

    test "preserves relative order of multiple issues sharing one path" do
      {form_state, form} =
        form_pair(Form.submit(Form.new(code_definition()), %{"code" => "ab"}))

      # Derive the expected order from Form.issues/1 directly, rather than
      # hardcoding JSV's current emission order, so this pins normalization's
      # stability guarantee and not an incidental validator detail.
      raw_messages_at_path =
        form_state
        |> Form.issues()
        |> Enum.filter(&(&1.path.segments == ["code"]))
        |> Enum.map(& &1.message)

      # Guard the fixture: this test only discriminates a stable vs. unstable
      # sort if there are at least two issues sharing the path.
      assert match?([_, _], raw_messages_at_path)

      assert {:ok, issues} = StateView.issues(form_state, form)

      normalized_messages_at_path =
        issues
        |> Enum.filter(&(&1.path.segments == ["code"]))
        |> Enum.map(& &1.message)

      assert normalized_messages_at_path == raw_messages_at_path
    end
  end

  describe "a non-Formentation source" do
    test "answers the contract with its own action semantics" do
      source = %Formentation.SourceFixture{
        params: %{"a" => "1"},
        action: :commit,
        submitted?: true,
        visibility: %{["a"] => :hide},
        issues: {:ok, [%StateView.Issue{path: InstancePath.new!([]), message: "root problem"}]}
      }

      form = Phoenix.HTML.FormData.to_form(source, as: "payload")

      assert form.action == :commit
      assert StateView.submitted?(source, form)
      assert StateView.issue_visibility(source, form, InstancePath.new!(["a"])) == :hide
      assert StateView.issue_visibility(source, form, InstancePath.new!(["b"])) == :default
      assert {:ok, [%StateView.Issue{message: "root problem"}]} = StateView.issues(source, form)
    end

    test "defaults to an unavailable, unsubmitted, policy-free view" do
      source = %Formentation.SourceFixture{}
      form = Phoenix.HTML.FormData.to_form(source, as: "payload")

      refute StateView.submitted?(source, form)
      assert StateView.issue_visibility(source, form, InstancePath.new!([])) == :default
      assert StateView.issues(source, form) == :unavailable
    end

    test "exposes scalar values and errors through Phoenix" do
      source = %Formentation.SourceFixture{
        params: %{"a" => "typed"},
        errors: [a: {"is invalid", []}]
      }

      form = Phoenix.HTML.FormData.to_form(source, as: "payload")

      assert form[:a].value == "typed"
      assert form[:a].errors == [{"is invalid", []}]
    end

    test "nests wherever its params hold a map" do
      source = %Formentation.SourceFixture{params: %{"address" => %{"street" => "Main"}}}
      form = Phoenix.HTML.FormData.to_form(source, as: "payload")

      assert [nested] = Phoenix.HTML.FormData.to_form(source, form, :address, [])
      assert nested.name == "payload[address]"
      assert nested.id == "payload_address"
      assert nested[:street].value == "Main"
    end

    test "refuses nested access where its params hold no map" do
      source = %Formentation.SourceFixture{params: %{"a" => "typed"}}
      form = Phoenix.HTML.FormData.to_form(source, as: "payload")

      for field <- [:a, :address] do
        assert_raise ArgumentError, ~r/nests only where its params hold a map/, fn ->
          Phoenix.HTML.FormData.to_form(source, form, field, [])
        end
      end
    end
  end
end
