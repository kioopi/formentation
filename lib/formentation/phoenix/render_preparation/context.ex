defmodule Formentation.Phoenix.RenderPreparation.Context do
  @moduledoc """
  The projection context `RenderPreparation` resolves before traversing, and
  the cursor it carries while traversing.

  Not part of the public API — reached only through `RenderPreparation.prepare/2`
  and `prepare_at/3`. Kept out of the published docs by `mix.exs`, but
  documented here because "which projection are we in" is a self-contained
  question worth understanding on its own: a form arrives either as a native
  projected form, which carries its own definition and root path, or as a
  generic form plus an explicit `definition:`, and everything downstream —
  root validation, the semantic-node index, the DOM namespace — follows from
  that one branch.

  `path` holds raw segments; an `%InstancePath{}` is built only where a path
  crosses into `StateView`. `root_form` and `source` stay pinned to the form
  handed to `prepare/2` or `prepare_at/3`, never a nested form built during
  traversal. Preparation always starts with the cursor on the projection root,
  so a freshly resolved context has `path == root_path`; only traversal moves
  `path`, and only through this module.
  """

  alias Formentation.{Definition, Info, InstancePath}
  alias Formentation.Phoenix.{ProjectedForm, StateView}

  @missing_namespace ~S"""
                     Formentation cannot mint DOM ids without a namespace. Give the form a name or an id
                     (`to_form(state, as: "payload")` or `to_form(state, id: "payload")`), or pass
                     `dom_namespace:` to Formentation.Phoenix.fields/1 or Formentation.Phoenix.field/1.
                     """
                     |> String.trim()

  @enforce_keys [
    :definition,
    :root_form,
    :source,
    :path,
    :root_path,
    :root_instance_path,
    :semantic_nodes,
    :dom_namespace
  ]

  defstruct @enforce_keys

  @type t :: %__MODULE__{
          definition: Definition.t(),
          root_form: Phoenix.HTML.Form.t(),
          source: StateView.t(),
          path: [InstancePath.segment()],
          root_path: [InstancePath.segment()],
          root_instance_path: InstancePath.t(),
          semantic_nodes: %{InstancePath.t() => term()},
          dom_namespace: String.t()
        }

  @doc """
  Resolves the projection context for `form`.

  A native projected form is authoritative: its source carries the definition
  and the projection root, and a redundant `definition:` in `opts` is accepted
  only when it is identical. A generic form requires an explicit `definition:`
  and always projects from the root.

  Namespace resolution is `opts[:dom_namespace]`, then `form.id`, then
  `form.name`; it raises when none is available. Namespace *shape* is not
  checked here — `DOMIdentity` rejects an unusable namespace when an id is
  minted.

  ## Example

      iex> {:ok, definition, []} =
      ...>   Formentation.compile(
      ...>     %{kind: :object, properties: [{"email", %{kind: :string}}]},
      ...>     adapter: Formentation.Source.Map
      ...>   )
      iex> form = Phoenix.HTML.FormData.to_form(%{}, as: "payload")
      iex> ctx = Formentation.Phoenix.RenderPreparation.Context.resolve(form, definition: definition)
      iex> {ctx.root_path, ctx.path, ctx.dom_namespace}
      {[], [], "payload"}
  """
  @spec resolve(Phoenix.HTML.Form.t(), keyword()) :: t()
  def resolve(%Phoenix.HTML.Form{} = form, opts) when is_list(opts) do
    case ProjectedForm.native_context(form) do
      {:ok, %{definition: definition, root_path: %{segments: root_path}}} ->
        validate_native_definition!(definition, Keyword.get(opts, :definition))
        build(definition, form, root_path, opts)

      :not_native ->
        build(generic_definition!(opts), form, [], opts)

      {:error, reason} ->
        raise ArgumentError,
              "Phoenix form is not a valid Formentation projection (#{inspect(reason)}); " <>
                "rebuild it through Phoenix.HTML.FormData.to_form/2 or inputs_for"
    end
  end

  defp build(definition, form, root_path, opts) do
    validate_projection_root!(definition, root_path)

    %__MODULE__{
      definition: definition,
      root_form: form,
      source: form.source,
      path: root_path,
      root_path: root_path,
      root_instance_path: InstancePath.new!(root_path),
      semantic_nodes: Info.semantic_node_index(definition),
      dom_namespace: dom_namespace!(form, opts)
    }
  end

  # Validating the root is not the same as building it. semantic_kind/2 is a
  # single index lookup; RenderPreparation's presentation_root_at/2
  # materializes the descriptor tree recursively, and only prepare/2 consumes
  # that. Building it here made every prepare_at/3 call — that is, every
  # field/1 render — pay for whole-body presentation traversal to answer a
  # question about one node.
  defp validate_projection_root!(definition, root_path) do
    case Info.semantic_kind(definition, root_path) do
      :object ->
        :ok

      nil ->
        raise ArgumentError, "projected form root #{inspect(root_path)} does not exist"

      :unsupported ->
        raise ArgumentError, "projected form root #{inspect(root_path)} is unsupported"

      _field ->
        raise ArgumentError, "projected form root #{inspect(root_path)} is not an object"
    end
  end

  defp validate_native_definition!(_native, nil), do: :ok
  defp validate_native_definition!(native, native), do: :ok

  defp validate_native_definition!(_native, _provided) do
    raise ArgumentError,
          "the native form source definition is authoritative; remove the redundant definition assign"
  end

  defp generic_definition!(opts) do
    case Keyword.get(opts, :definition) do
      %Definition{} = definition ->
        definition

      _other ->
        raise ArgumentError,
              "render preparation requires a native projected form or a generic form plus definition:"
    end
  end

  defp dom_namespace!(form, opts) do
    Keyword.get(opts, :dom_namespace) || form.id || form.name ||
      raise ArgumentError, @missing_namespace
  end
end
