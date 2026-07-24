defmodule Formentation.JSONSchema.Validator do
  @moduledoc """
  Thin adapter around the chosen JSON Schema validator, JSV (D-008).
  Validates a schema document against the draft 2020-12 metaschema —
  offline, via JSV's embedded metaschemas — and translates structured
  validator output into diagnostics. The single swap point if the
  validator choice is ever revisited.
  """

  alias Formentation.{Diagnostic, InstancePath, Issue, TemplatePath}

  @dialect "https://json-schema.org/draft/2020-12/schema"

  # Structural error kinds that merely point at failing children; the
  # leaf errors carry the actual keyword violations.
  @structural_kinds [:properties]

  @metaschema_root JSV.build!(%{"$ref" => @dialect}, atoms: false)

  @doc "The JSON Schema dialect this adapter validates against."
  @spec dialect() :: String.t()
  def dialect, do: @dialect

  @doc """
  Validates a schema document against the draft 2020-12 metaschema —
  offline, via JSV's embedded metaschemas. Returns `{:error, diagnostics}`
  with one `:invalid_schema` diagnostic per leaf violation.
  """
  @spec validate_schema(map()) :: :ok | {:error, [Diagnostic.t()]}
  def validate_schema(schema) when is_map(schema) do
    case JSV.validate(schema, @metaschema_root, cast: false) do
      {:ok, _} -> :ok
      {:error, validation_error} -> {:error, to_diagnostics(validation_error)}
    end
  end

  defp to_diagnostics(validation_error) do
    validation_error
    |> JSV.normalize_error()
    |> error_units()
    |> Enum.map(&to_diagnostic/1)
  end

  # `JSV.normalize_error/1` (with the default `keys: :atoms`) returns a tree,
  # not a flat list: each unit names the instance location it validated and
  # carries `errors`, where each error either resolves to a message or
  # delegates to further sub-schemas via nested `details` (how JSV represents
  # allOf/anyOf/$ref combinators — the metaschema itself is built from these).
  # Only the deepest errors — the ones without further `details` — name an
  # actual metaschema violation, so we walk the tree and keep those.
  defp error_units(%{details: details}) when is_list(details) do
    Enum.flat_map(details, &leaf_units/1)
  end

  defp leaf_units(%{instanceLocation: location, errors: errors}) do
    Enum.flat_map(errors, &leaf_units_from_error(location, &1))
  end

  defp leaf_units_from_error(_location, %{details: nested}) when is_list(nested) do
    Enum.flat_map(nested, &leaf_units/1)
  end

  defp leaf_units_from_error(location, error) do
    [%{location: location, message: unit_message(error)}]
  end

  defp to_diagnostic(%{location: location, message: message}) do
    bare_pointer = String.trim_leading(location, "#")

    %Diagnostic{
      severity: :error,
      code: :invalid_schema,
      message: message,
      origin: {:json_schema, bare_pointer},
      template_path: %TemplatePath{segments: []}
    }
  end

  defp unit_message(%{message: message}) when is_binary(message), do: message
  defp unit_message(_error), do: "schema does not conform to #{@dialect}"

  @doc """
  Builds the opaque instance-validation artifact stored on the
  definition. Call only after `validate_schema/1` has accepted the
  schema document. A schema can pass the metaschema and still fail to
  build an instance validator — e.g. a dangling local `$ref`, or any
  remote `$ref` (fetching is disabled) — so this degrades gracefully
  instead of raising: `{:error, reason}` carries a human-readable
  message built from JSV's build error.
  """
  @spec build_instance_validator(map()) :: {:ok, term()} | {:error, String.t()}
  def build_instance_validator(schema) when is_map(schema) do
    case JSV.build(schema, atoms: false) do
      {:ok, validator} -> {:ok, validator}
      {:error, reason} -> {:error, build_error_message(reason)}
    end
  end

  defp build_error_message(reason) when is_exception(reason), do: Exception.message(reason)
  defp build_error_message(reason), do: inspect(reason)

  @doc """
  Known spec deviation: issue codes pass JSV's `kind` atoms through
  directly instead of mapping them through a fixed allowlist — safe
  because JSV kinds are library compile-time literals, never derived
  from input.
  """
  @spec validate_instance(term(), map()) :: [Issue.t()]
  def validate_instance(validator, instance) do
    case JSV.validate(instance, validator, cast: false) do
      {:ok, _} -> []
      {:error, %JSV.ValidationError{errors: errors}} -> Enum.flat_map(errors, &to_issues/1)
    end
  end

  defp to_issues(%JSV.Validator.Error{kind: kind}) when kind in @structural_kinds, do: []

  # One issue per missing property, at that property's path — the field
  # shows its own error instead of blaming the parent object.
  defp to_issues(%JSV.Validator.Error{kind: :required} = error) do
    object_path = Enum.reverse(error.data_path)

    for name <- Keyword.fetch!(error.args, :required) do
      %Issue{
        path: InstancePath.new!(object_path ++ [name]),
        code: :required,
        message: error.formatter.format_error(:required, %{required: [name]}, error.data),
        source: :schema
      }
    end
  end

  defp to_issues(%JSV.Validator.Error{} = error) do
    [
      %Issue{
        path: InstancePath.new!(Enum.reverse(error.data_path)),
        code: error.kind,
        message: error.formatter.format_error(error.kind, Map.new(error.args), error.data),
        source: :schema
      }
    ]
  end
end
