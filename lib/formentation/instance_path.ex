defmodule Formentation.InstancePath do
  @moduledoc """
  Position of a value in a concrete data instance.

  Segments are strings (object properties) or non-negative integers
  (collection indexes, Milestone B). Never atoms.
  """

  alias Formentation.TemplatePath

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

  @doc """
  The path one segment below this one; raises `ArgumentError` on a
  segment that is not a string or a non-negative integer.

      iex> Formentation.InstancePath.new!(["addresses"]) |> Formentation.InstancePath.child(0)
      %Formentation.InstancePath{segments: ["addresses", 0]}
  """
  @spec child(t(), segment()) :: t()
  def child(%__MODULE__{segments: segments}, segment) do
    validate_segment!(segment)
    %__MODULE__{segments: segments ++ [segment]}
  end

  @doc """
  The path one segment above this one; the root is its own parent, which
  keeps callers total.

      iex> Formentation.InstancePath.new!(["addresses", 0]) |> Formentation.InstancePath.parent()
      %Formentation.InstancePath{segments: ["addresses"]}
  """
  @spec parent(t()) :: t()
  def parent(%__MODULE__{segments: []} = path), do: path

  def parent(%__MODULE__{segments: segments}) do
    %__MODULE__{segments: Enum.drop(segments, -1)}
  end

  @doc """
  Projects this instance path onto the template: every integer segment
  becomes the `:item` marker, strings pass through. Total and
  deterministic; the reverse mapping is one-to-many (one template node,
  many occurrences). Projection is syntactic — whether the projected path
  names a real node still requires a definition lookup.

      iex> Formentation.InstancePath.new!(["addresses", 0, "street"]) |> Formentation.InstancePath.to_template()
      %Formentation.TemplatePath{segments: ["addresses", :item, "street"]}
  """
  @spec to_template(t()) :: TemplatePath.t()
  def to_template(%__MODULE__{segments: segments}) do
    TemplatePath.new!(
      Enum.map(segments, fn
        index when is_integer(index) -> :item
        name -> name
      end)
    )
  end

  @doc """
  Whether `ancestor` is equal to or a strict ancestor of `descendant`,
  compared segment by segment. Never a string prefix — `["tag"]` is not
  an ancestor of `["tags"]`, and the integer `0` is not the string `"0"`.

      iex> Formentation.InstancePath.ancestor_or_self?(
      ...>   Formentation.InstancePath.new!(["tags"]),
      ...>   Formentation.InstancePath.new!(["tags", 0])
      ...> )
      true

      iex> Formentation.InstancePath.ancestor_or_self?(
      ...>   Formentation.InstancePath.new!(["tag"]),
      ...>   Formentation.InstancePath.new!(["tags"])
      ...> )
      false
  """
  @spec ancestor_or_self?(t(), t()) :: boolean()
  def ancestor_or_self?(%__MODULE__{segments: ancestor}, %__MODULE__{segments: descendant}) do
    List.starts_with?(descendant, ancestor)
  end

  defp validate_segment!(segment) when is_binary(segment), do: :ok
  defp validate_segment!(segment) when is_integer(segment) and segment >= 0, do: :ok

  defp validate_segment!(other) do
    raise ArgumentError, "invalid instance path segment: #{inspect(other)}"
  end
end
