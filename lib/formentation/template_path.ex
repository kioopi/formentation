defmodule Formentation.TemplatePath do
  @moduledoc """
  Static position of a node in the declaration template.

  Segments are strings naming object properties, plus the fixed internal
  marker `:item` reserved for collections (Milestone B). No other atoms:
  declaration property names are untrusted input and must never become
  atoms.
  """

  @enforce_keys [:segments]
  defstruct segments: []

  @typedoc "One path step: an object property name, or `:item` under a collection."
  @type segment :: String.t() | :item

  @typedoc "A static position in the declaration template."
  @type t :: %__MODULE__{segments: [segment()]}

  @doc """
  Builds a path, raising `ArgumentError` on any segment that is not a
  string or the `:item` marker.

      iex> Formentation.TemplatePath.new!(["profile"])
      %Formentation.TemplatePath{segments: ["profile"]}
  """
  @spec new!([segment()]) :: t()
  def new!(segments) when is_list(segments) do
    Enum.each(segments, &validate_segment!/1)
    %__MODULE__{segments: segments}
  end

  @doc """
  The path one property step below this one.

      iex> Formentation.TemplatePath.new!(["profile"]) |> Formentation.TemplatePath.child("age")
      %Formentation.TemplatePath{segments: ["profile", "age"]}
  """
  @spec child(t(), String.t()) :: t()
  def child(%__MODULE__{segments: segments}, segment) when is_binary(segment) do
    %__MODULE__{segments: segments ++ [segment]}
  end

  @doc """
  The path one collection-item step below this one.

      iex> Formentation.TemplatePath.new!(["addresses"]) |> Formentation.TemplatePath.item()
      %Formentation.TemplatePath{segments: ["addresses", :item]}
  """
  @spec item(t()) :: t()
  def item(%__MODULE__{segments: segments}) do
    %__MODULE__{segments: segments ++ [:item]}
  end

  @doc """
  Whether `instance` is an occurrence of this template path: segmentwise,
  `:item` matches any integer index and a string matches only itself.
  Equivalent to `Formentation.InstancePath.to_template(instance) == template`.

      iex> Formentation.TemplatePath.matches?(
      ...>   Formentation.TemplatePath.new!(["addresses", :item]),
      ...>   Formentation.InstancePath.new!(["addresses", 0])
      ...> )
      true
  """
  @spec matches?(t(), Formentation.InstancePath.t()) :: boolean()
  def matches?(%__MODULE__{segments: template}, %Formentation.InstancePath{segments: instance}) do
    length(template) == length(instance) and
      template
      |> Enum.zip(instance)
      |> Enum.all?(fn
        {:item, index} -> is_integer(index)
        {name, segment} -> name == segment
      end)
  end

  defp validate_segment!(segment) when is_binary(segment), do: :ok
  defp validate_segment!(:item), do: :ok

  defp validate_segment!(other) do
    raise ArgumentError, "invalid template path segment: #{inspect(other)}"
  end
end
