defmodule Formentation do
  @moduledoc """
  Compile form declarations from pluggable sources into a static,
  source-independent `Formentation.Definition`, and query it through
  `Formentation.Info`.
  """

  alias Formentation.{Definition, Diagnostic}

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
      ...>   Formentation.compile(declaration, adapter: Formentation.Source.Map)
      iex> Formentation.Info.fields(definition) |> Enum.map(& &1.name)
      ["name", "age"]
  """
  @spec compile(term(), keyword()) ::
          {:ok, Definition.t(), [Diagnostic.t()]} | {:error, [Diagnostic.t()]}
  def compile(source, opts) do
    {selection, opts} = take_adapter!(opts)
    adapter = resolve_adapter!(selection)
    adapter.compile(source, opts)
  end

  defp resolve_adapter!(:map), do: Formentation.Source.Map
  defp resolve_adapter!(adapter), do: adapter

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
