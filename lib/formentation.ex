defmodule Formentation do
  @moduledoc """
  Compile form declarations from pluggable sources into a static,
  source-independent `Formentation.Definition`, and query it through
  `Formentation.Info`.
  """

  alias Formentation.{Definition, Diagnostic, Form}

  @form_initialization_options [:defaults]
  @form_owned_options [:data | @form_initialization_options]

  @doc """
  Compiles a declaration using the source adapter given as `adapter:`;
  remaining options pass through to the adapter.

  Returns `{:ok, definition, diagnostics}` — `diagnostics` carries
  warnings that did not prevent compilation — or `{:error, diagnostics}`
  when the declaration could not be compiled.

      iex> declaration = %{
      ...>   kind: :object,
      ...>   properties: [
      ...>     {"name", %{kind: :string}},
      ...>     {"age", %{kind: :integer}}
      ...>   ]
      ...> }
      iex> {:ok, definition, []} =
      ...>   Formentation.compile(declaration, adapter: :map)
      iex> Formentation.Info.fields(definition) |> Enum.map(& &1.name)
      ["name", "age"]

  Built-in adapters have stable symbolic selectors — `:map` for
  `Formentation.Source.Map`, `:json_schema` for `Formentation.JSONSchema`.
  Third-party adapters remain reachable by module.
  """
  @spec compile(term(), keyword()) ::
          {:ok, Definition.t(), [Diagnostic.t()]} | {:error, [Diagnostic.t()]}
  def compile(source, opts) do
    {selection, opts} = take_adapter!(opts)
    adapter = resolve_adapter!(selection)
    adapter.compile(source, opts)
  end

  @doc """
  Compiles a declaration and initializes a `Formentation.Form` in one step.

  `adapter:` selects the source adapter as in `compile/2`. `data:` is the
  initial instance (defaults to `%{}`); `defaults:` passes through to
  `Formentation.Form.new/3`. All remaining options pass through to the
  adapter unchanged.

  Returns `{:ok, form, diagnostics}` on successful compilation, or
  `{:error, diagnostics}` without initializing a form when compilation
  fails.

      iex> declaration = %{
      ...>   kind: :object,
      ...>   properties: [{"name", %{kind: :string}}]
      ...> }
      iex> {:ok, form, []} =
      ...>   Formentation.form(declaration, adapter: :map, data: %{"name" => "Ada"})
      iex> form.original
      %{"name" => "Ada"}
  """
  @spec form(term(), keyword()) ::
          {:ok, Form.t(), [Diagnostic.t()]} | {:error, [Diagnostic.t()]}
  def form(source, opts) do
    data = Keyword.get(opts, :data, %{})
    initialization_opts = Keyword.take(opts, @form_initialization_options)
    compiler_opts = Keyword.drop(opts, @form_owned_options)

    case compile(source, compiler_opts) do
      {:ok, definition, diagnostics} ->
        {:ok, Form.new(definition, data, initialization_opts), diagnostics}

      {:error, diagnostics} ->
        {:error, diagnostics}
    end
  end

  defp resolve_adapter!(:map), do: Formentation.Source.Map
  defp resolve_adapter!(:json_schema), do: Formentation.JSONSchema

  defp resolve_adapter!(adapter) when is_atom(adapter) do
    # `ensure_compiled/1`, not `ensure_loaded?/1`: an adapter defined in the
    # caller's own project may still be in flight in the same parallel-compiler
    # run when a definition is compiled at compile time. `ensure_loaded?/1` does
    # not wait for it and would reject a perfectly valid adapter, intermittently.
    if match?({:module, _}, Code.ensure_compiled(adapter)) and
         function_exported?(adapter, :compile, 2) do
      adapter
    else
      raise ArgumentError, adapter_error_message(adapter)
    end
  end

  defp resolve_adapter!(other), do: raise(ArgumentError, adapter_error_message(other))

  defp adapter_error_message(value) do
    "unsupported adapter #{inspect(value)}; use :map, :json_schema, or a module exporting compile/2"
  end

  defp take_adapter!(opts) do
    missing = make_ref()

    case Keyword.pop(opts, :adapter, missing) do
      {^missing, _opts} ->
        raise ArgumentError,
              "missing required :adapter option; use :map, :json_schema, or an adapter module"

      pair ->
        pair
    end
  end
end
