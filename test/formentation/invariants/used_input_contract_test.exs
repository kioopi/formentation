defmodule Formentation.Phoenix.UsedInputContractTest do
  use ExUnit.Case, async: true

  # D-014's recorded obligation: verify our Phoenix-compatible params view
  # and usage rules against the real Phoenix.Component.used_input?/1 —
  # not a reimplementation of its marker convention. Spec §8 records why
  # the two systems agree everywhere user-visible.

  import Phoenix.Component, only: [used_input?: 1]

  alias Formentation.Form
  alias Formentation.Form.Params
  alias Formentation.Phoenix.Render.{Node, Preparation}
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

    {:ok, definition, []} =
      Formentation.compile(declaration, adapter: Formentation.Source.Map)

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

  test "preparation's state-view visibility agrees with used_input? on every scalar after a single transition" do
    # This proves agreement only for the single-transition case, where
    # `form.usage` starts empty and the D-014 usage merge in
    # `Form.transition/2` (`Map.merge(form.usage, normalized.usage)`) is
    # therefore a no-op — accumulated usage and the current params' marker
    # convention coincide. It is not a general proof: see "accumulated
    # usage diverges from used_input? after a second transition" below for
    # the case where a later transition omits a previously-used field and
    # the two systems deliberately disagree.
    form_state =
      transitioned(%{
        "title" => "",
        "_unused_title" => "",
        "address" => %{"street" => "s", "number" => "", "_unused_number" => ""}
      })

    form = FormData.to_form(form_state, [])
    nested = hd(FormData.to_form(form_state, form, :address, []))

    pairs = [
      {form[:title], ["title"]},
      {nested[:street], ["address", "street"]},
      {nested[:number], ["address", "number"]}
    ]

    for {field, segments} <- pairs do
      state_view_says =
        Formentation.Phoenix.StateView.issue_visibility(
          form_state,
          form,
          Formentation.InstancePath.new!(segments)
        ) == :show

      assert state_view_says == used_input?(field),
             "state view and used_input?/1 disagree at #{inspect(segments)}"
    end
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

  test "accumulated usage diverges from used_input? after a second transition" do
    # used_input?/1 reads only the CURRENT Phoenix params. Form.usage/2 is
    # ACCUMULATED across transitions (Form.transition/2 merges usage:
    # `Map.merge(form.usage, normalized.usage)`, never replaces it), so
    # once a field has been used, it stays used even if a later
    # transition's payload omits it entirely.
    #
    # This is a deliberate design decision, not a bug: Formentation.Form
    # owns the complete D-014 visibility policy, and "the user has
    # interacted with this field at some point" is what usage means (see
    # `Form.usage/2`'s doc). The previous, used_input?-based rule would
    # have HIDDEN this error at t2, because used_input? forgets a field
    # the moment a payload stops mentioning it — even though the field
    # was genuinely edited and genuinely fails validation. Do not change
    # the implementation to restore that old behaviour.
    schema = %{
      "type" => "object",
      "required" => ["title"],
      "properties" => %{
        "title" => %{"type" => "string", "minLength" => 4},
        "other" => %{"type" => "string"}
      }
    }

    {:ok, definition, []} =
      Formentation.compile(schema, adapter: Formentation.Source.JSONSchema)

    form_t1 =
      Form.transition(Form.new(definition), %Params{
        values: %{"title" => "ab", "other" => "x"},
        event: :change
      })

    # t2's payload drops "title" entirely; only "other" changes.
    form_t2 = Form.transition(form_t1, %Params{values: %{"other" => "y"}, event: :change})

    phoenix_form_t2 = FormData.to_form(form_t2, as: "payload")

    # used_input? forgets "title" was ever touched...
    refute used_input?(phoenix_form_t2[:title])
    # ...but Form.show_issues?/2 still shows it, because accumulated
    # usage still says :used.
    assert Form.show_issues?(form_t2, ["title"]) == true

    # And the user-visible consequence, through render preparation, is that
    # the (now-:required, since "title" is absent from the candidate)
    # error is shown.
    plan = Preparation.prepare(phoenix_form_t2, definition: definition)

    title_node =
      Enum.find(plan.root.children, &match?(%Node.Field{field: %{field: :title}}, &1))

    assert %Node.Field{show_errors?: true} = title_node
  end
end
