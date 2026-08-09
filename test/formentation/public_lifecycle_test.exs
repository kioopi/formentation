defmodule Formentation.PublicLifecycleTest do
  use ExUnit.Case, async: true

  # The North Star's ordinary public lifecycle, crossed end to end in one
  # flow: Formentation.form/2 -> Phoenix.Component.to_form/2 ->
  # Formentation.Phoenix.fields/1 -> Formentation.Form.submit/2.
  #
  # Every other test in this suite exercises one of those seams in
  # isolation. This one exists to prove they compose — that the four
  # public nouns are sufficient on their own, with no definition assign,
  # no concrete source module, and no adapter internals in sight.
  #
  # See https://github.com/kioopi/formentation/issues/46 (Wave 4, §1).

  import Formentation.HTMLAssertions
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Formentation.{Diagnostic, Form, InstancePath}
  alias Formentation.Phoenix.DOMIdentity

  @declaration %{
    kind: :object,
    required: ["email"],
    properties: [
      {"email", %{kind: :string, role: :email, title: "Email", min_length: 1}},
      {"age", %{kind: :integer, title: "Age"}}
    ]
  }

  # The same declaration without `min_length: 1`: a required string that
  # permits an empty value. Worth telling the caller about, but not an
  # error — so it compiles successfully *and* warns.
  @warning_declaration %{
    kind: :object,
    required: ["email"],
    properties: [{"email", %{kind: :string, role: :email, title: "Email"}}]
  }

  # The caller owns `as` and `id`; the renderer derives DOM identity from
  # the namespace the caller chose, never from a definition it was handed
  # separately.
  defp render_projection(form_state) do
    render_component(&Formentation.Phoenix.fields/1,
      form: Phoenix.Component.to_form(form_state, as: "payload", id: "payload")
    )
  end

  defp field_id(path, part),
    do: DOMIdentity.field("payload", InstancePath.new!(path), part)

  test "the ordinary lifecycle carries a form from declaration to a typed submission" do
    # 1. A symbolic built-in selector compiles and initializes in one
    #    step. This declaration is deliberately warning-free; that
    #    diagnostics *survive* a successful compile is pinned by the
    #    second test below, which this `== []` alone would not prove.
    assert {:ok, form_state, diagnostics} =
             Formentation.form(@declaration,
               adapter: :map,
               data: %{"email" => "ada@example.com"}
             )

    assert diagnostics == []

    # 2. The Form projects through the standard Phoenix entry point and
    #    renders with no `definition:` assign.
    doc = parse!(render_projection(form_state))

    assert_no_duplicate_ids(doc)
    assert [email] = Floki.find(doc, "input[name='payload[email]']")
    assert Floki.attribute(email, "value") == ["ada@example.com"]

    # 3. Caller-owned `as` and `id` are authoritative for transport names
    #    and for renderer-owned DOM identity.
    assert Floki.attribute(email, "id") == [field_id(["email"], :control)]

    # 4. An invalid raw value survives redisplay, and its issue renders.
    assert {:error, submitted} =
             Form.submit(form_state, %{"email" => "ada@example.com", "age" => "36x"})

    invalid_doc = parse!(render_projection(submitted))

    assert [age] = Floki.find(invalid_doc, "input[name='payload[age]']")
    assert Floki.attribute(age, "value") == ["36x"]
    assert [_field_errors] = Floki.find(invalid_doc, "##{field_id(["age"], :errors)}")
    assert [_summary] = Floki.find(invalid_doc, "[role='alert']")

    # 5. A valid submit returns decoded types, not transport strings, and
    #    the application decision comes from Form.submit/2 itself.
    assert {:ok, candidate, _submitted_form} =
             Form.submit(form_state, %{"email" => "ada@example.com", "age" => "36"})

    assert candidate == %{"email" => "ada@example.com", "age" => 36}
  end

  test "a successful compilation carries its warnings through to the caller" do
    assert {:ok, %Form{}, [diagnostic]} =
             Formentation.form(@warning_declaration, adapter: :map)

    assert %Diagnostic{severity: :warning, code: :required_permits_empty} = diagnostic
  end
end
