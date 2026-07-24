defmodule Formentation.InstancePath do
  @moduledoc """
  Position of a value in a concrete data instance.

  Segments are strings (object properties) or non-negative integers
  (collection indexes, Milestone B). Never atoms.
  """

  @enforce_keys [:segments]
  defstruct segments: []

  @typedoc "One path step: an object property name or a collection index."
  @type segment :: String.t() | non_neg_integer()

  @typedoc "A position in a concrete data instance."
  @type t :: %__MODULE__{segments: [segment()]}

  @doc """
  Builds a path, raising `ArgumentError` on any segment that is not a
  string or a non-negative integer — atoms never enter path vocabulary.

      iex> Formentation.InstancePath.new!(["addresses", 0])
      %Formentation.InstancePath{segments: ["addresses", 0]}
  """
  @spec new!([segment()]) :: t()
  def new!(segments) when is_list(segments) do
    Enum.each(segments, &validate_segment!/1)
    %__MODULE__{segments: segments}
  end

  defp validate_segment!(segment) when is_binary(segment), do: :ok
  defp validate_segment!(segment) when is_integer(segment) and segment >= 0, do: :ok

  defp validate_segment!(other) do
    raise ArgumentError, "invalid instance path segment: #{inspect(other)}"
  end
end
