defmodule Formentation.Form.Decoder do
  @moduledoc """
  Decodes one transition's normalized domain params into the per-path
  transport and operation maps (D-009). Enumerates declared fields
  through `Formentation.Occurrence.occurrences/2` over the incoming
  params — the enumeration collections extend (D-051).

  Input is the `.domain_params` view of
  `Formentation.Form.Transport.normalize/1`; raw Phoenix params and the
  `Formentation.Form.Params` envelope never reach this module.
  """

  alias Formentation.{Definition, InstancePath, Issue, Occurrence}
  alias Formentation.Definition.Semantic
  alias Formentation.Form.{Codec, FieldState}

  @doc """
  The `{transports, operations, issues}` triple for `domain_params`,
  each map keyed by `Formentation.InstancePath`. `issues` carries only
  decode failures.

      iex> {:ok, definition, []} =
      ...>   Formentation.compile(
      ...>     %{kind: :object, properties: [{"age", %{kind: :integer}}]},
      ...>     adapter: Formentation.Source.Map
      ...>   )
      iex> {transports, operations, issues} =
      ...>   Formentation.Form.Decoder.decode(definition, %{"age" => "42"})
      iex> transports[Formentation.InstancePath.new!(["age"])]
      {:provided, "42"}
      iex> operations[Formentation.InstancePath.new!(["age"])]
      {:set, 42}
      iex> issues
      %{}
  """
  @spec decode(Definition.t(), map()) ::
          {%{InstancePath.t() => FieldState.transport()},
           %{InstancePath.t() => FieldState.operation()}, %{InstancePath.t() => [Issue.t()]}}
  def decode(%Definition{} = definition, domain_params) when is_map(domain_params) do
    definition
    |> Occurrence.occurrences(domain_params)
    |> Enum.filter(fn {entry, _path} -> entry.kind == :field end)
    |> Enum.reduce({%{}, %{}, %{}}, fn {entry, path}, {transports, operations, issues} ->
      transport = transport_at(domain_params, path)
      operation = operation_for(entry.node, transport, path)

      issues =
        case operation do
          {:invalid, issue} -> Map.put(issues, path, [issue])
          _other -> issues
        end

      {Map.put(transports, path, transport), Map.put(operations, path, operation), issues}
    end)
  end

  # D-016: read-only fields do not participate in the replace scope —
  # whatever the transport carried, the original value is kept.
  defp operation_for(%Semantic.Field{read_only?: true}, _transport, _path), do: :keep
  defp operation_for(_node, :not_provided, _path), do: :unset
  defp operation_for(node, {:provided, raw}, path), do: Codec.decode(node.value_type, raw, path)

  defp transport_at(params, %InstancePath{segments: segments}) do
    {parent_segments, [name]} = Enum.split(segments, -1)

    case params_at(params, parent_segments) do
      {:ok, parent} -> fetch_transport(parent, name)
      :error -> :not_provided
    end
  end

  defp fetch_transport(params, name) when is_map(params) do
    case Map.fetch(params, name) do
      {:ok, raw} -> {:provided, raw}
      :error -> :not_provided
    end
  end

  defp fetch_transport(_params, _name), do: :not_provided

  defp params_at(params, []), do: {:ok, params}

  defp params_at(params, [segment | rest]) when is_map(params) do
    case Map.fetch(params, segment) do
      {:ok, child} -> params_at(child, rest)
      :error -> :error
    end
  end

  defp params_at(_params, _segments), do: :error
end
