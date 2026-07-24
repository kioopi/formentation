defmodule Formentation.JSONPointer do
  @moduledoc """
  RFC 6901 JSON Pointer building for origins and diagnostics. Segments
  escape `~` → `~0` and `/` → `~1`; `~` first so `/` escapes are never
  double-escaped.
  """

  @doc """
  Joins already-unescaped segments into an absolute JSON Pointer.

      iex> Formentation.JSONPointer.join(["properties", "notes"])
      "/properties/notes"

      iex> Formentation.JSONPointer.join(["a/b", "c~d"])
      "/a~1b/c~0d"

  The empty segment list is the whole-document pointer:

      iex> Formentation.JSONPointer.join([])
      ""
  """
  @spec join([String.t()]) :: String.t()
  def join(segments) when is_list(segments) do
    IO.iodata_to_binary(Enum.map(segments, &["/", escape_segment(&1)]))
  end

  @doc """
  Escapes one segment for embedding in a pointer.

      iex> Formentation.JSONPointer.escape_segment("~/")
      "~0~1"
  """
  @spec escape_segment(String.t()) :: String.t()
  def escape_segment(segment) when is_binary(segment) do
    segment
    |> String.replace("~", "~0")
    |> String.replace("/", "~1")
  end
end
