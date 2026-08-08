defmodule Formentation.Phoenix.Render.Preparation.ContextTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  doctest Formentation.Phoenix.Render.Preparation.Context

  alias Formentation.{Form, InstancePath}
  alias Formentation.Phoenix.Render.Preparation.Context
  alias Phoenix.HTML.FormData

  defp compile!(declaration) do
    {:ok, definition, _diagnostics} =
      Formentation.compile(declaration, adapter: Formentation.Definition.Source.Map)

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

  defp root_context, do: Context.resolve(native_form(nested_definition()), [])

  defp nested_context do
    definition = nested_definition()
    state = Form.new(definition, %{"address" => %{"street" => "Elm"}})
    root = FormData.to_form(state, as: "asset[payload]", id: "asset_payload")
    [address] = FormData.to_form(state, root, :address, [])

    Context.resolve(address, [])
  end

  describe "cursor_to/2" do
    test "a path below the root moves the cursor and reports the descent" do
      {descent, moved} = Context.cursor_to(root_context(), ["address"])

      assert descent == ["address"]
      assert moved.path == ["address"]
    end

    test "the root itself descends nothing and leaves the cursor at the root" do
      ctx = root_context()
      {descent, moved} = Context.cursor_to(ctx, [])

      assert descent == []
      assert moved.path == ctx.root_path
    end

    test "a nested projection reports the descent relative to its own root" do
      ctx = nested_context()
      assert ctx.root_path == ["address"]

      {descent, moved} = Context.cursor_to(ctx, ["address"])

      assert descent == []
      assert moved.path == ["address"]
    end

    test "a path above the nested root parks the cursor at the root" do
      ctx = nested_context()
      {descent, moved} = Context.cursor_to(ctx, [])

      assert descent == []
      assert moved.path == ["address"]
    end

    test "a sibling of the nested root parks the cursor at the root" do
      ctx = nested_context()
      {descent, moved} = Context.cursor_to(ctx, ["title"])

      assert descent == []
      assert moved.path == ["address"]
    end

    test "never rewrites root_path or root_instance_path" do
      ctx = root_context()
      {_descent, moved} = Context.cursor_to(ctx, ["address"])

      assert moved.root_path == ctx.root_path
      assert moved.root_instance_path == ctx.root_instance_path
    end
  end

  describe "enter/2" do
    test "the current path is :self" do
      ctx = root_context()

      assert Context.enter(ctx, ctx.path) == :self
    end

    test "a direct child reports its segment and moves the cursor" do
      assert {:child, "address", moved} = Context.enter(root_context(), ["address"])
      assert moved.path == ["address"]
    end

    test "a grandchild is rejected" do
      assert Context.enter(root_context(), ["address", "street"]) == :error
    end

    test "a same-length sibling is rejected" do
      {:child, _segment, at_address} = Context.enter(root_context(), ["address"])

      assert Context.enter(at_address, ["title"]) == :error
    end

    test "an unrelated path is rejected" do
      assert Context.enter(root_context(), ["nope", "deeper"]) == :error
    end
  end

  describe "summary_view/1" do
    test "returns exactly the keys Summary declares" do
      view = Context.summary_view(root_context())

      assert Map.keys(view) |> Enum.sort() ==
               [:definition, :root_form, :root_instance_path, :source] |> Enum.sort()
    end

    test "carries the context's own values" do
      ctx = root_context()
      view = Context.summary_view(ctx)

      assert view.definition == ctx.definition
      assert view.root_form == ctx.root_form
      assert view.root_instance_path == ctx.root_instance_path
      assert view.source == ctx.source
    end
  end

  # A definition deep enough that generated paths can be above, at, and below
  # a nested projection root. Paths are drawn from its real segment names so
  # every generated case is one traversal could actually produce.
  defp deep_definition do
    compile!(%{
      kind: :object,
      properties: [
        {"title", %{kind: :string}},
        {"address",
         %{
           kind: :object,
           properties: [
             {"street", %{kind: :string}},
             {"geo", %{kind: :object, properties: [{"lat", %{kind: :string}}]}}
           ]
         }}
      ]
    })
  end

  defp deep_context(root_segments) do
    definition = deep_definition()
    state = Form.new(definition, %{"address" => %{"geo" => %{"lat" => "51.5"}}})
    root = FormData.to_form(state, as: "payload", id: "payload")

    Enum.reduce(root_segments, root, fn segment, form ->
      key = %{"address" => :address, "geo" => :geo}[segment]
      [nested] = FormData.to_form(state, form, key, [])
      nested
    end)
    |> Context.resolve([])
  end

  @object_paths [[], ["address"], ["address", "geo"]]
  @nested_object_paths [["address"], ["address", "geo"]]
  @all_paths @object_paths ++ [["title"], ["address", "street"], ["address", "geo", "lat"]]

  # Precomputed rather than filtered inside the property: the outside-the-
  # projection space is six pairs, and drawing root and target from separate
  # generators would need either a nested `check all` (100 x 100 runs over
  # those six cases, each recompiling the definition) or a filter that
  # discards most of what it draws. One generator over the real space also
  # shrinks to a counterexample you can read.
  @outside_pairs for root <- @nested_object_paths,
                     target <- @all_paths,
                     not List.starts_with?(target, root),
                     do: {root, target}

  describe "cursor properties" do
    property "a resolved context starts on its own root" do
      check all(root <- member_of(@object_paths)) do
        ctx = deep_context(root)

        assert ctx.path == ctx.root_path
        assert ctx.root_path == ctx.root_instance_path.segments
      end
    end

    property "descent always reconstructs the moved cursor from the root" do
      check all(
              root <- member_of(@object_paths),
              target <- member_of(@all_paths)
            ) do
        ctx = deep_context(root)
        {descent, moved} = Context.cursor_to(ctx, target)

        assert ctx.root_path ++ descent == moved.path
      end
    end

    property "a path outside the projection parks the cursor at the root" do
      check all({root, target} <- member_of(@outside_pairs)) do
        ctx = deep_context(root)

        assert {[], moved} = Context.cursor_to(ctx, target)
        assert moved.path == ctx.root_path
      end
    end

    property "cursor_to never disturbs the root fields" do
      check all(
              root <- member_of(@object_paths),
              target <- member_of(@all_paths)
            ) do
        ctx = deep_context(root)
        {_descent, moved} = Context.cursor_to(ctx, target)

        assert moved.root_path == ctx.root_path
        assert moved.root_instance_path == ctx.root_instance_path
        assert moved.definition == ctx.definition
        assert moved.dom_namespace == ctx.dom_namespace
      end
    end

    property "enter accepts exactly the direct children of the cursor" do
      check all(
              root <- member_of(@object_paths),
              target <- member_of(@all_paths)
            ) do
        ctx = deep_context(root)

        direct_child? =
          Enum.drop(target, -1) == ctx.path and length(target) == length(ctx.path) + 1

        case Context.enter(ctx, target) do
          :self -> assert target == ctx.path
          {:child, segment, _moved} -> assert direct_child? and segment == List.last(target)
          :error -> refute direct_child? or target == ctx.path
        end
      end
    end
  end
end
