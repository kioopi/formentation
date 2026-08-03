defmodule Formentation.Phoenix.DOMIdentityDecoder do
  @moduledoc false

  alias Formentation.InstancePath

  def decode(id) when is_binary(id) do
    case decode_tokens(String.split(id, "--")) do
      {:ok, identity} -> identity
      :error -> invalid!(id)
    end
  end

  defp decode_tokens(["ftn", namespace, "field", part | identity]) do
    with {:ok, namespace} <- namespace(namespace),
         {:ok, path} <- path(identity),
         {:ok, part} <- field_part(part) do
      {:ok, {:field, namespace, path, part}}
    end
  end

  defp decode_tokens(["ftn", namespace, "object", part | identity]) do
    with {:ok, namespace} <- namespace(namespace),
         {:ok, path} <- path(identity),
         {:ok, part} <- container_part(part) do
      {:ok, {:object, namespace, path, part}}
    end
  end

  defp decode_tokens(["ftn", namespace, "group", part, layout_id | enclosing_path]) do
    with {:ok, namespace} <- namespace(namespace),
         {:ok, layout_id} <- unescape(layout_id),
         {:ok, path} <- path(enclosing_path),
         {:ok, part} <- container_part(part) do
      {:ok, {:group, namespace, layout_id, path, part}}
    end
  end

  defp decode_tokens(_tokens), do: :error

  defp namespace(token) do
    case unescape(token) do
      {:ok, namespace} when byte_size(namespace) > 0 -> {:ok, namespace}
      _other -> :error
    end
  end

  defp field_part("control"), do: {:ok, :control}
  defp field_part("container"), do: {:ok, :container}
  defp field_part("help"), do: {:ok, :help}
  defp field_part("errors"), do: {:ok, :errors}

  defp field_part("option_" <> token) do
    case Integer.parse(token) do
      {index, ""} when index >= 0 -> canonical_option(index, token)
      _other -> :error
    end
  end

  defp field_part(_part), do: :error

  defp container_part("container"), do: {:ok, :container}
  defp container_part("help"), do: {:ok, :help}
  defp container_part(_part), do: :error

  defp path(tokens) do
    with {:ok, segments} <- segments(tokens) do
      {:ok, InstancePath.new!(segments)}
    end
  end

  defp segments(tokens) do
    Enum.reduce_while(tokens, {:ok, []}, fn token, {:ok, acc} ->
      case segment(token) do
        {:ok, segment} -> {:cont, {:ok, [segment | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, segments} -> {:ok, Enum.reverse(segments)}
      :error -> :error
    end
  end

  defp segment(<<digit, _rest::binary>> = token) when digit in ?0..?9 do
    case Integer.parse(token) do
      {segment, ""} -> canonical_segment(segment, token)
      _other -> :error
    end
  end

  defp segment(token), do: unescape(token)

  defp unescape(token), do: unescape(token, [])

  defp unescape(<<>>, acc), do: {:ok, acc |> Enum.reverse() |> :erlang.iolist_to_binary()}

  defp unescape(<<"-", hex::binary-size(2), rest::binary>>, acc) do
    with {:ok, byte} <- hex_byte(hex), do: unescape(rest, [<<byte>> | acc])
  end

  defp unescape(<<"-", _rest::binary>>, _acc), do: :error

  defp unescape(<<byte, rest::binary>>, acc)
       when byte in ?A..?Z or byte in ?a..?z or byte in ?0..?9 do
    unescape(rest, [<<byte>> | acc])
  end

  defp unescape(<<?_, rest::binary>>, acc), do: unescape(rest, ["_" | acc])
  defp unescape(_token, _acc), do: :error

  defp hex_byte(<<first, second>>) when first in ?0..?9 or first in ?A..?F do
    if second in ?0..?9 or second in ?A..?F do
      {:ok, String.to_integer(<<first, second>>, 16)}
    else
      :error
    end
  end

  defp hex_byte(_hex), do: :error

  defp canonical_option(index, token) do
    if Integer.to_string(index) == token, do: {:ok, {:option, index}}, else: :error
  end

  defp canonical_segment(segment, token) do
    if Integer.to_string(segment) == token, do: {:ok, segment}, else: :error
  end

  defp invalid!(id), do: raise(ArgumentError, "invalid DOM identity: #{inspect(id)}")
end
