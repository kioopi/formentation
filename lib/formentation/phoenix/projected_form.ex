defmodule Formentation.Phoenix.ProjectedForm do
  @moduledoc false

  alias Formentation.{Form, InstancePath}

  @path_key :__formentation__

  @doc false
  @spec put_root_path(keyword(), [InstancePath.segment()]) :: keyword()
  def put_root_path(options, segments) when is_list(options) and is_list(segments) do
    %InstancePath{segments: segments} = InstancePath.new!(segments)
    Keyword.put(options, @path_key, segments)
  end

  @doc false
  @spec native_context(Phoenix.HTML.Form.t()) ::
          {:ok,
           %{
             definition: Formentation.Definition.t(),
             state: Form.t(),
             root_path: InstancePath.t()
           }}
          | :not_native
          | {:error, :missing_root_path | {:invalid_root_path, term()}}
  def native_context(%Phoenix.HTML.Form{source: %Form{} = state, options: options}) do
    with {:ok, segments} <- fetch_root_path(options),
         {:ok, root_path} <- instance_path(segments) do
      {:ok, %{definition: state.definition, state: state, root_path: root_path}}
    end
  end

  def native_context(%Phoenix.HTML.Form{}), do: :not_native

  @doc false
  @spec root_segments!(Phoenix.HTML.Form.t()) :: [InstancePath.segment()]
  def root_segments!(form) do
    case native_context(form) do
      {:ok, %{root_path: %InstancePath{segments: segments}}} ->
        segments

      :not_native ->
        raise_invalid_projection!(:not_native)

      {:error, reason} ->
        raise_invalid_projection!(reason)
    end
  end

  defp fetch_root_path(options) when is_list(options) do
    case Keyword.fetch(options, @path_key) do
      {:ok, segments} -> {:ok, segments}
      :error -> {:error, :missing_root_path}
    end
  end

  defp fetch_root_path(_options), do: {:error, :missing_root_path}

  defp instance_path(segments) when is_list(segments) do
    {:ok, InstancePath.new!(segments)}
  rescue
    ArgumentError -> {:error, {:invalid_root_path, segments}}
  end

  defp instance_path(segments), do: {:error, {:invalid_root_path, segments}}

  defp raise_invalid_projection!(reason) do
    raise ArgumentError,
          "Phoenix form is not a valid Formentation projection (#{inspect(reason)}); " <>
            "rebuild it through Phoenix.HTML.FormData.to_form/2 or inputs_for"
  end
end
