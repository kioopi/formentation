defmodule Formentation.Phoenix.DOMIdentity do
  @moduledoc """
  Renderer-owned DOM identities for Phoenix markup.

  Ids use the stable `ftn--namespace--kind--part--identity...` grammar. The
  format is safe to depend on in tests, selectors, and stylesheets; the
  constructors themselves remain internal until the Phase 3 prepared-view
  contract settles.

  Field `:control` ids name controls whose label and error-summary anchor target
  is the control itself. `:container` names composite-widget containers such as a
  radio group's fieldset. `:hidden_input` also uses `:control`.
  """

  alias Formentation.InstancePath

  @type field_part :: :control | :container | :help | :errors | {:option, non_neg_integer()}
  @type container_part :: :container | :help

  @doc """
  Returns the DOM id of a field element.

      iex> path = Formentation.InstancePath.new!(["notes"])
      iex> Formentation.Phoenix.DOMIdentity.field("asset_payload", path, :help)
      "ftn--asset_payload--field--help--notes"

      iex> path = Formentation.InstancePath.new!(["notes_help"])
      iex> Formentation.Phoenix.DOMIdentity.field("asset_payload", path, :control)
      "ftn--asset_payload--field--control--notes_help"
  """
  @spec field(String.t(), InstancePath.t(), field_part()) :: String.t()
  def field(namespace, %InstancePath{segments: segments}, part) do
    encode(namespace, "field", field_part!(part), segments)
  end

  @doc """
  Returns the DOM id of an object container or help element.

      iex> path = Formentation.InstancePath.new!(["address"])
      iex> Formentation.Phoenix.DOMIdentity.object("asset_payload", path, :container)
      "ftn--asset_payload--object--container--address"
  """
  @spec object(String.t(), InstancePath.t(), container_part()) :: String.t()
  def object(namespace, %InstancePath{segments: segments}, part) do
    encode(namespace, "object", container_part!(part, "object"), segments)
  end

  @doc """
  Returns the DOM id of a presentation-group container or help element.

      iex> path = Formentation.InstancePath.new!([])
      iex> Formentation.Phoenix.DOMIdentity.group("asset_payload", "/#electrical", path, :container)
      "ftn--asset_payload--group--container---2F-23electrical"
  """
  @spec group(String.t(), String.t(), InstancePath.t(), container_part()) :: String.t()
  def group(namespace, layout_id, %InstancePath{segments: segments}, part) do
    validate_layout_id!(layout_id)
    encode(namespace, "group", container_part!(part, "group"), [layout_id | segments])
  end

  defp encode(namespace, kind, part, identity) do
    validate_namespace!(namespace)

    ["ftn", escape(namespace), kind, part | Enum.map(identity, &token/1)]
    |> Enum.join("--")
  end

  defp field_part!(:control), do: "control"
  defp field_part!(:container), do: "container"
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

  defp validate_layout_id!(layout_id) when is_binary(layout_id), do: :ok

  defp validate_layout_id!(layout_id) do
    raise ArgumentError,
          "group DOM identity layout id must be a binary, got: #{inspect(layout_id)}"
  end

  defp token(segment) when is_integer(segment) and segment >= 0, do: Integer.to_string(segment)
  defp token(segment) when is_binary(segment), do: escape(segment)

  defp token(segment) do
    raise ArgumentError, "invalid DOM identity path segment: #{inspect(segment)}"
  end

  defp escape(<<byte, rest::binary>>) when byte in ?0..?9 do
    :erlang.iolist_to_binary([hex(byte), escape_rest(rest)])
  end

  defp escape(binary), do: binary |> escape_rest() |> :erlang.iolist_to_binary()

  defp escape_rest(<<>>), do: []
  defp escape_rest(<<?_, rest::binary>>), do: ["_" | escape_rest(rest)]

  defp escape_rest(<<byte, rest::binary>>)
       when byte in ?A..?Z or byte in ?a..?z or byte in ?0..?9 do
    [<<byte>> | escape_rest(rest)]
  end

  defp escape_rest(<<byte, rest::binary>>), do: [hex(byte) | escape_rest(rest)]

  # Fixed-width by construction: every `-` is followed by exactly two hex
  # digits, so `--` can only ever be a delimiter.
  defp hex(byte), do: "-" <> Base.encode16(<<byte>>)
end
