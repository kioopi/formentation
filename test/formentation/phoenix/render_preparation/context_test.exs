defmodule Formentation.Phoenix.RenderPreparation.ContextTest do
  use ExUnit.Case, async: true

  doctest Formentation.Phoenix.RenderPreparation.Context

  alias Formentation.{Form, InstancePath}
  alias Formentation.Phoenix.RenderPreparation.Context
  alias Phoenix.HTML.FormData

  defp compile!(declaration) do
    {:ok, definition, _diagnostics} =
      Formentation.compile(declaration, adapter: Formentation.Source.Map)

    definition
  end

  defp flat_definition do
    compile!(%{
      kind: :object,
      properties: [
        {"serial_number", %{kind: :string}},
        {"notes", %{kind: :string}}
      ]
    })
  end

  defp nested_definition do
    compile!(%{
      kind: :object,
      properties: [
        {"title", %{kind: :string}},
        {"address", %{kind: :object, properties: [{"street", %{kind: :string}}]}}
      ]
    })
  end

  defp native_form(definition, opts \\ [as: "payload"]),
    do: FormData.to_form(Form.new(definition), opts)

  defp generic_form(opts \\ [as: "payload"]), do: FormData.to_form(%{}, opts)

  describe "resolve/2 on a native projected form" do
    test "derives the definition and root path from the form source" do
      definition = flat_definition()
      ctx = Context.resolve(native_form(definition), [])

      assert ctx.definition == definition
      assert ctx.root_path == []
      assert ctx.root_instance_path == InstancePath.new!([])
      assert ctx.path == []
    end

    test "pins root_form and source to the form it was handed" do
      definition = flat_definition()
      form = native_form(definition)
      ctx = Context.resolve(form, [])

      assert ctx.root_form == form
      assert ctx.source == form.source
    end

    test "indexes every semantic node" do
      definition = nested_definition()
      ctx = Context.resolve(native_form(definition), [])

      assert ctx.semantic_nodes == Formentation.Info.semantic_node_index(definition)
    end
  end

  describe "resolve/2 on a generic form" do
    test "uses the definition supplied in opts" do
      definition = flat_definition()
      ctx = Context.resolve(generic_form(), definition: definition)

      assert ctx.definition == definition
      assert ctx.root_path == []
    end

    test "raises when no definition is supplied" do
      assert_raise ArgumentError,
                   ~r/requires a native projected form or a generic form plus definition:/,
                   fn -> Context.resolve(generic_form(), []) end
    end
  end

  describe "resolve/2 rejections" do
    test "rejects an explicit definition that differs from the native source's" do
      form = native_form(flat_definition())

      assert_raise ArgumentError,
                   ~r/native form source definition is authoritative/,
                   fn -> Context.resolve(form, definition: nested_definition()) end
    end

    test "accepts an explicit definition identical to the native source's" do
      definition = flat_definition()
      ctx = Context.resolve(native_form(definition), definition: definition)

      assert ctx.definition == definition
    end

    test "rejects a native form with malformed projection metadata" do
      form = native_form(flat_definition())
      broken = %{form | options: []}

      assert_raise ArgumentError,
                   ~r/not a valid Formentation projection/,
                   fn -> Context.resolve(broken, []) end
    end
  end

  describe "resolve/2 namespace selection" do
    test "prefers an explicit override" do
      form = native_form(flat_definition(), as: "payload", id: "form_id")
      ctx = Context.resolve(form, dom_namespace: "explicit")

      assert ctx.dom_namespace == "explicit"
    end

    test "a nil override falls through to the form id" do
      form = native_form(flat_definition(), as: "payload", id: "form_id")
      ctx = Context.resolve(form, dom_namespace: nil)

      assert ctx.dom_namespace == "form_id"
    end

    test "the form id wins over the form name" do
      form = native_form(flat_definition(), as: "payload", id: "form_id")

      assert Context.resolve(form, []).dom_namespace == "form_id"
    end

    test "falls back to the form name when there is no id" do
      form = %{native_form(flat_definition()) | id: nil}

      assert Context.resolve(form, []).dom_namespace == "payload"
    end

    test "raises when neither an override, an id, nor a name is available" do
      form = %{native_form(flat_definition(), []) | id: nil, name: nil}

      assert_raise ArgumentError,
                   ~r/Formentation cannot mint DOM ids without a namespace/,
                   fn -> Context.resolve(form, []) end
    end

    # Shape validation is DOMIdentity's job, deferred until an id is minted.
    # Asserted here so nobody adds an eager check to Context and changes
    # which error message callers see.
    test "accepts an empty namespace, deferring rejection to DOMIdentity" do
      form = native_form(flat_definition())

      assert Context.resolve(form, dom_namespace: "").dom_namespace == ""
    end
  end

  describe "resolve/2 native and generic agreement" do
    test "both branches agree on definition and semantic nodes" do
      definition = flat_definition()
      native = Context.resolve(native_form(definition), [])
      generic = Context.resolve(generic_form(), definition: definition)

      assert native.definition == generic.definition
      assert native.semantic_nodes == generic.semantic_nodes
      assert native.root_path == generic.root_path
    end
  end
end
