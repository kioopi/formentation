defmodule Formentation.Phoenix.DOMIdentity do
  @moduledoc false

  alias Formentation.InstancePath

  @type field_part :: :control | :help | :errors | {:option, non_neg_integer()}
  @type container_part :: :container | :help

  @doc false
  @spec field(String.t(), InstancePath.t(), field_part()) :: String.t()
  def field(namespace, %InstancePath{segments: segments}, part) do
    encode(namespace, "field", field_part!(part), segments)
  end

  @doc false
  @spec object(String.t(), InstancePath.t(), container_part()) :: String.t()
  def object(namespace, %InstancePath{segments: segments}, part) do
    encode(namespace, "object", container_part!(part, "object"), segments)
  end

  @doc false
  @spec group(String.t(), String.t(), InstancePath.t(), container_part()) :: String.t()
  def group(namespace, layout_id, %InstancePath{segments: segments}, part)
      when is_binary(layout_id) do
    encode(namespace, "group", container_part!(part, "group"), [layout_id | segments])
  end

  def group(_namespace, layout_id, _path, _part) do
    raise ArgumentError,
          "group DOM identity layout id must be a binary, got: #{inspect(layout_id)}"
  end

  defp encode(namespace, kind, part, identity) do
    validate_namespace!(namespace)

    ["ftn", escape(namespace), kind, part | Enum.map(identity, &token/1)]
    |> Enum.join("--")
  end

  defp field_part!(:control), do: "control"
  defp field_part!(:help), do: "help"
  defp field_part!(:errors), do: "errors"
  defp field_part!({:option, index}) when is_integer(index) and index >= 0, do: "option_#{index}"

  defp field_part!(part) do
    raise ArgumentError, "invalid field DOM identity part: #{inspect(part)}"
  end

  defp container_part!(:container, _owner), do: "container"
  defp container_part!(:help, _owner), do: "help"

  defp container_part!(part, owner) do
    raise ArgumentError, "invalid #{owner} DOM identity part: #{inspect(part)}"
  end

  defp validate_namespace!(namespace) when is_binary(namespace) and byte_size(namespace) > 0,
    do: :ok

  defp validate_namespace!(namespace) do
    raise ArgumentError,
          "DOM identity requires a non-empty binary namespace, got: #{inspect(namespace)}"
  end

  defp token(segment) when is_integer(segment) and segment >= 0, do: Integer.to_string(segment)
  defp token(segment) when is_binary(segment), do: escape(segment)

  defp token(segment) do
    raise ArgumentError, "invalid DOM identity path segment: #{inspect(segment)}"
  end

  defp escape(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.with_index()
    |> Enum.map_join(fn {byte, index} -> escape_byte(byte, index) end)
  end

  defp escape_byte(?_, _index), do: "_"

  defp escape_byte(byte, 0) when byte in ?A..?Z or byte in ?a..?z do
    <<byte>>
  end

  defp escape_byte(byte, index)
       when index > 0 and (byte in ?A..?Z or byte in ?a..?z or byte in ?0..?9) do
    <<byte>>
  end

  defp escape_byte(byte, _index), do: "-" <> Base.encode16(<<byte>>)
end
