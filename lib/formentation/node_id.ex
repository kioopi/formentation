defmodule Formentation.NodeId do
  @moduledoc """
  Deterministic node IDs from template paths (D-007). Segments escape the
  ID vocabulary — RFC 6901's `~` → `~0` and `/` → `~1`, plus `#` → `~2`
  as a Formentation extension for the presentation-group suffix — so no
  legal property or group name can collide with a path separator or a
  group ID.
  """

  alias Formentation.{JSONPointer, TemplatePath}

  @doc """
  The ID of the node at `path`; the root ID is `"/"`.

      iex> Formentation.NodeId.from_path(Formentation.TemplatePath.new!([]))
      "/"

      iex> Formentation.NodeId.from_path(Formentation.TemplatePath.new!(["profile", "name"]))
      "/profile/name"
  """
  @spec from_path(TemplatePath.t()) :: String.t()
  def from_path(%TemplatePath{segments: []}), do: "/"

  def from_path(%TemplatePath{segments: segments}) do
    IO.iodata_to_binary(Enum.map(segments, &["/", escape_segment(&1)]))
  end

  @doc """
  The ID of a presentation group: the owning object's path plus the
  `#`-separated group id.

      iex> Formentation.NodeId.group(Formentation.TemplatePath.new!([]), "contact")
      "/#contact"
  """
  @spec group(TemplatePath.t(), String.t()) :: String.t()
  def group(%TemplatePath{} = path, group_id) when is_binary(group_id) do
    from_path(path) <> "#" <> escape_segment(group_id)
  end

  @doc """
  Escapes one segment for the ID vocabulary.

      iex> Formentation.NodeId.escape_segment("a/b#c")
      "a~1b~2c"
  """
  @spec escape_segment(String.t()) :: String.t()
  def escape_segment(segment) when is_binary(segment) do
    segment
    |> JSONPointer.escape_segment()
    |> String.replace("#", "~2")
  end
end
