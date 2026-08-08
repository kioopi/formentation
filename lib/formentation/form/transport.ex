defmodule Formentation.Form.Transport do
  @moduledoc """
  Pure transport normalization (D-014): splits raw browser params into
  domain params with Phoenix transport metadata stripped, a byte-identical
  Phoenix-compatible view for `form.params`, and per-path usage extracted
  from LiveView's `_unused_` marker convention. String and map processing
  only — zero Phoenix dependency. Never fabricates interaction state:
  paths the params do not mention simply have no usage entry, and
  `:unknown` is a lookup default in `Formentation.Form`, not a stored
  value here.

  Key validation covers the keys the normalizer processes: domain keys at
  any depth must be strings. Metadata entries (`_unused_*`, `_csrf_token`,
  `_target`, `_persistent_id`) are stripped by key and their values carried into
  `phoenix_params` verbatim, never inspected — they cannot reach domain
  decoding or usage.
  """

  alias Formentation.InstancePath

  defmodule Normalized do
    @moduledoc """
    The three views `Formentation.Form.Transport.normalize/1` splits raw
    params into: cleaned `domain_params` for decoding, the
    byte-identical `phoenix_params` view for `used_input?/1`, and
    per-path `usage`.
    """
    @enforce_keys [:domain_params, :phoenix_params, :usage]
    defstruct [:domain_params, :phoenix_params, :usage]

    @type t :: %__MODULE__{
            domain_params: map(),
            phoenix_params: map(),
            usage: %{InstancePath.t() => :used | :unused}
          }
  end

  @unused_prefix "_unused_"
  @metadata_keys ["_csrf_token", "_target", "_persistent_id"]

  @doc """
  Splits raw browser params into the three views transitions consume.

      iex> n = Formentation.Form.Transport.normalize(%{
      ...>   "name" => "Ada",
      ...>   "_unused_name" => "",
      ...>   "_csrf_token" => "token"
      ...> })
      iex> n.domain_params
      %{"name" => "Ada"}
      iex> n.usage
      %{%Formentation.InstancePath{segments: ["name"]} => :unused}
      iex> n.phoenix_params["_csrf_token"]
      "token"
  """
  @spec normalize(map()) :: Normalized.t()
  def normalize(values) when is_map(values) do
    %Normalized{
      domain_params: strip(values),
      phoenix_params: values,
      usage: usage(values, [])
    }
  end

  defp strip(values) do
    for {key, value} <- values, check_key!(key), not metadata_key?(key), into: %{} do
      {key, if(is_map(value), do: strip(value), else: value)}
    end
  end

  defp check_key!(key) when is_binary(key), do: true

  defp check_key!(key) do
    raise ArgumentError, "params keys must be strings, got: #{inspect(key)}"
  end

  defp metadata_key?(key) do
    key in @metadata_keys or String.starts_with?(key, @unused_prefix)
  end

  defp usage(values, prefix) do
    Enum.reduce(values, %{}, fn {key, value}, acc ->
      if metadata_key?(key) do
        acc
      else
        entry(acc, values, key, value, prefix)
      end
    end)
  end

  defp entry(acc, values, key, value, prefix) when is_map(value) do
    descendants = usage(value, prefix ++ [key])
    status = if :used in Map.values(descendants), do: :used, else: :unused
    status = if map_size(descendants) == 0, do: marker_status(values, key), else: status

    acc
    |> Map.merge(descendants)
    |> Map.put(InstancePath.new!(prefix ++ [key]), status)
  end

  defp entry(acc, values, key, _value, prefix) do
    Map.put(acc, InstancePath.new!(prefix ++ [key]), marker_status(values, key))
  end

  defp marker_status(values, key) do
    if Map.has_key?(values, @unused_prefix <> key), do: :unused, else: :used
  end
end
