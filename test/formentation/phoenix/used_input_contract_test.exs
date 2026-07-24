defmodule Formentation.Phoenix.UsedInputContractTest do
  use ExUnit.Case, async: true

  # D-014's recorded obligation: verify our Phoenix-compatible params view
  # and usage rules against the real Phoenix.Component.used_input?/1 —
  # not a reimplementation of its marker convention. Spec §8 records why
  # the two systems agree everywhere user-visible.

  import Phoenix.Component, only: [used_input?: 1]

  alias Formentation.{Form, Params}
  alias Phoenix.HTML.FormData

  defp nested_definition do
    declaration = %{
      kind: :object,
      properties: [
        {"title", %{kind: :string}},
        {"address",
         %{
           kind: :object,
           properties: [{"street", %{kind: :string}}, {"number", %{kind: :integer}}]
         }}
      ]
    }

    {:ok, definition, []} = Formentation.compile(declaration, adapter: Formentation.Source.Map)
    definition
  end

  defp transitioned(values) do
    Form.transition(Form.new(nested_definition()), %Params{values: values, event: :change})
  end

  test "scalar usage agrees with used_input? under the marker convention" do
    form_state =
      transitioned(%{"title" => "", "_unused_title" => "", "address" => %{"street" => "s"}})

    form = FormData.to_form(form_state, [])

    assert used_input?(form[:title]) == false
    assert Form.usage(form_state, ["title"]) == :unused

    nested = hd(FormData.to_form(form_state, form, :address, []))
    assert used_input?(nested[:street]) == true
    assert Form.usage(form_state, ["address", "street"]) == :used
  end

  test "parent usage propagates from any used descendant on both sides" do
    used_child =
      transitioned(%{"address" => %{"street" => "s", "number" => "", "_unused_number" => ""}})

    form = FormData.to_form(used_child, [])
    assert used_input?(form[:address]) == true
    assert Form.usage(used_child, ["address"]) == :used

    all_unused =
      transitioned(%{
        "address" => %{
          "street" => "",
          "_unused_street" => "",
          "number" => "",
          "_unused_number" => ""
        }
      })

    form = FormData.to_form(all_unused, [])
    assert used_input?(form[:address]) == false
    assert Form.usage(all_unused, ["address"]) == :unused
  end

  test "markers survive the nested projection" do
    form_state =
      transitioned(%{"address" => %{"street" => "", "_unused_street" => "", "number" => "7"}})

    form = FormData.to_form(form_state, [])
    nested = hd(FormData.to_form(form_state, form, :address, []))

    assert nested.params["_unused_street"] == ""
    assert used_input?(nested[:street]) == false
    assert used_input?(nested[:number]) == true
    assert Form.usage(form_state, ["address", "street"]) == :unused
    assert Form.usage(form_state, ["address", "number"]) == :used
  end

  test "marker-less params (plain HTTP posts) count as used on both sides" do
    form_state = transitioned(%{"title" => "t", "address" => %{"street" => "s"}})
    form = FormData.to_form(form_state, [])

    assert used_input?(form[:title]) == true
    assert Form.usage(form_state, ["title"]) == :used
  end

  test "paths absent from the params are unused/unknown on both sides" do
    form_state = transitioned(%{"title" => "t"})
    form = FormData.to_form(form_state, [])

    assert used_input?(form[:address]) == false
    assert Form.usage(form_state, ["address"]) == :unknown
    assert Form.show_issues?(form_state, ["address", "number"]) == false
  end

  test "the group-node visibility gate is Formentation's, not Phoenix's" do
    # used_input? answers true for a group with a used child at :change,
    # but show_issues? gates group/root issues on submit — deliberate, so
    # the first keystroke cannot surface object-level errors. Core
    # components never render object-level errors, so nothing
    # user-visible disagrees (spec §8).
    form_state = transitioned(%{"address" => %{"street" => "s"}})
    form = FormData.to_form(form_state, [])

    assert used_input?(form[:address]) == true
    assert Form.show_issues?(form_state, ["address"]) == false
  end
end
