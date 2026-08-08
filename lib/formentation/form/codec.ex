defmodule Formentation.Form.Codec do
  @moduledoc """
  Scalar decoders from transport encodings to JSON values (D-010).

  `decode/3` turns one raw submitted value into a decode operation.
  `:keep` never comes from a codec — it is the absence of a
  transition-supplied operation. Posture is strict with trim: typed
  controls trim surrounding whitespace and require full-token parses;
  string controls preserve input verbatim, because the value is the data.
  Native values of the target JSON type pass through, so transitions stay
  usable from IEx without stringifying. `nil` is always rejected: null is
  explicit-only and never produced by decoding.
  """

  alias Formentation.{InstancePath, Issue}

  @typedoc "The scalar JSON value types codecs decode into."
  @type value_type :: :string | :integer | :number | :boolean

  @typedoc """
  What a decoded transport value means for the instance: set a value,
  unset the key, or record the decode failure.
  """
  @type operation :: {:set, term()} | :unset | {:invalid, Issue.t()}

  @integer_grammar ~r/^[+-]?[0-9]+$/
  @number_grammar ~r/^[+-]?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$/

  @doc """
  Decodes one raw submitted value into a decode operation (D-010).

  Typed controls trim and require a full-token parse; an all-whitespace
  string clears the key. String controls preserve input verbatim.

      iex> path = Formentation.InstancePath.new!(["age"])
      iex> Formentation.Form.Codec.decode(:integer, " 42 ", path)
      {:set, 42}
      iex> Formentation.Form.Codec.decode(:integer, "", path)
      :unset
      iex> Formentation.Form.Codec.decode(:string, "", path)
      {:set, ""}
      iex> Formentation.Form.Codec.decode(:boolean, "true", path)
      {:set, true}
      iex> {:invalid, issue} = Formentation.Form.Codec.decode(:integer, "4x", path)
      iex> {issue.code, issue.source}
      {:invalid_integer, :decode}
  """
  @spec decode(value_type(), term(), InstancePath.t()) :: operation()
  def decode(:string, raw, _path) when is_binary(raw), do: {:set, raw}

  def decode(:integer, raw, path) when is_binary(raw) do
    case String.trim(raw) do
      "" ->
        :unset

      trimmed ->
        if Regex.match?(@integer_grammar, trimmed) do
          {:set, String.to_integer(trimmed)}
        else
          invalid(:invalid_integer, "is not a valid integer", raw, path)
        end
    end
  end

  def decode(:integer, raw, _path) when is_integer(raw), do: {:set, raw}

  def decode(:number, raw, path) when is_binary(raw) do
    case String.trim(raw) do
      "" ->
        :unset

      trimmed ->
        cond do
          Regex.match?(@integer_grammar, trimmed) -> {:set, String.to_integer(trimmed)}
          Regex.match?(@number_grammar, trimmed) -> {:set, parse_float(trimmed)}
          true -> invalid(:invalid_number, "is not a valid number", raw, path)
        end
    end
  end

  def decode(:number, raw, _path) when is_integer(raw) or is_float(raw), do: {:set, raw}

  def decode(:boolean, raw, path) when is_binary(raw) do
    case String.trim(raw) do
      "" -> :unset
      "true" -> {:set, true}
      "false" -> {:set, false}
      _other -> invalid(:invalid_boolean, "is not a valid boolean", raw, path)
    end
  end

  def decode(:boolean, raw, _path) when is_boolean(raw), do: {:set, raw}

  def decode(_value_type, raw, path) do
    invalid(:invalid_value, "is not a decodable value", raw, path)
  end

  defp invalid(code, description, raw, path) do
    {:invalid,
     %Issue{path: path, code: code, message: "#{inspect(raw)} #{description}", source: :decode}}
  end

  defp parse_float(token) do
    normalized =
      token
      |> String.trim_leading("+")
      |> ensure_fraction()

    {value, ""} = Float.parse(normalized)
    value
  end

  defp ensure_fraction(token) do
    if String.contains?(token, ".") do
      token
    else
      String.replace(token, ~r/[eE]/, ".0e", global: false)
    end
  end
end
