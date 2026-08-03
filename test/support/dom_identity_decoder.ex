defmodule Formentation.Phoenix.DOMIdentityDecoder do
  @moduledoc false

  alias Formentation.InstancePath

  def decode(id) when is_binary(id) do
    case String.split(id, "--") do
      ["ftn", namespace, "field", part | identity] ->
        {:field, unescape(namespace), path(identity), field_part(part)}

      ["ftn", namespace, "object", part | identity] ->
        {:object, unescape(namespace), path(identity), container_part(part)}

      ["ftn", namespace, "group", part, layout_id | enclosing_path] ->
        {:group, unescape(namespace), unescape(layout_id), path(enclosing_path),
         container_part(part)}

      _other ->
        raise ArgumentError, "invalid DOM identity: #{inspect(id)}"
    end
  end

  defp field_part("control"), do: :control
  defp field_part("help"), do: :help
  defp field_part("errors"), do: :errors

  defp field_part("option_" <> index) do
    {index, ""} = Integer.parse(index)
    {:option, index}
  end

  defp container_part("container"), do: :container
  defp container_part("help"), do: :help

  defp path(tokens) do
    %InstancePath{segments: Enum.map(tokens, &segment/1)}
  end

  defp segment(<<digit, _rest::binary>> = token) when digit in ?0..?9,
    do: String.to_integer(token)

  defp segment(token), do: unescape(token)

  defp unescape(token), do: unescape(token, [])

  defp unescape(<<>>, acc), do: acc |> Enum.reverse() |> :erlang.iolist_to_binary()

  defp unescape(<<"-", hex::binary-size(2), rest::binary>>, acc) do
    unescape(rest, [<<String.to_integer(hex, 16)>> | acc])
  end

  defp unescape(<<byte, rest::binary>>, acc), do: unescape(rest, [<<byte>> | acc])
end
