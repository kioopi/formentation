defmodule Formentation.Source.JSONSchema.ValidatorTest do
  use ExUnit.Case, async: true

  alias Formentation.Diagnostic
  alias Formentation.{InstancePath, Issue}
  alias Formentation.Source.JSONSchema.Validator

  @dialect "https://json-schema.org/draft/2020-12/schema"

  test "reports the supported dialect" do
    assert Validator.dialect() == @dialect
  end

  test "a valid 2020-12 schema document passes" do
    schema = %{
      "$schema" => @dialect,
      "type" => "object",
      "properties" => %{"name" => %{"type" => "string", "minLength" => 4}},
      "required" => ["name"]
    }

    assert Validator.validate_schema(schema) == :ok
  end

  test "an invalid schema yields structured diagnostics pointing into the document" do
    schema = %{"type" => "object", "properties" => %{"name" => %{"type" => 12}}}

    assert {:error, diagnostics} = Validator.validate_schema(schema)
    assert diagnostics != []

    assert Enum.all?(diagnostics, fn diagnostic ->
             match?(
               %Diagnostic{severity: :error, code: :invalid_schema, origin: {:json_schema, _}},
               diagnostic
             ) and is_binary(diagnostic.message)
           end)

    # Verify that pointers are in bare RFC 6901 form (no leading #)
    assert Enum.all?(diagnostics, fn %Diagnostic{origin: {:json_schema, pointer}} ->
             refute String.starts_with?(pointer, "#")
             pointer == "" or String.starts_with?(pointer, "/")
           end)

    assert Enum.any?(diagnostics, fn %Diagnostic{origin: {:json_schema, pointer}} ->
             String.contains?(pointer, "/properties/name")
           end)
  end

  test "every metaschema violation is reported, not only the first" do
    schema = %{
      "type" => "object",
      "properties" => %{
        "a" => %{"type" => 12},
        "b" => %{"type" => ["not-a-type"]}
      }
    }

    assert {:error, diagnostics} = Validator.validate_schema(schema)

    pointers = for %Diagnostic{origin: {:json_schema, pointer}} <- diagnostics, do: pointer
    assert Enum.any?(pointers, &String.contains?(&1, "/properties/a"))
    assert Enum.any?(pointers, &String.contains?(&1, "/properties/b"))
  end

  describe "validate/2" do
    setup do
      schema = %{
        "type" => "object",
        "required" => ["serial_number", "condition"],
        "properties" => %{
          "serial_number" => %{"type" => "string", "minLength" => 4},
          "operating_hours" => %{"type" => "integer", "minimum" => 0},
          "nested" => %{
            "type" => "object",
            "required" => ["inner"],
            "properties" => %{"inner" => %{"type" => "string", "minLength" => 2}}
          }
        }
      }

      {:ok, validator} = Validator.build_instance_validator(schema)
      %{validator: validator}
    end

    test "a valid instance yields no issues", %{validator: validator} do
      assert Validator.validate(validator, %{
               "serial_number" => "PX-2044",
               "condition" => "good"
             }) == []
    end

    test "keyword violations carry the schema keyword and instance path", %{validator: validator} do
      issues =
        Validator.validate(validator, %{
          "serial_number" => "PX",
          "condition" => "good",
          "operating_hours" => -2
        })

      assert %Issue{
               code: :minLength,
               source: :validation,
               path: %InstancePath{segments: ["serial_number"]}
             } =
               Enum.find(issues, &(&1.code == :minLength))

      assert %Issue{code: :minimum, path: %InstancePath{segments: ["operating_hours"]}} =
               Enum.find(issues, &(&1.code == :minimum))
    end

    test "required lands one issue per missing property, at the property's path", %{
      validator: validator
    } do
      issues = Validator.validate(validator, %{})
      required = Enum.filter(issues, &(&1.code == :required))

      assert Enum.map(required, & &1.path.segments) |> Enum.sort() ==
               [["condition"], ["serial_number"]]

      assert Enum.all?(required, &(&1.message =~ "required"))
    end

    test "structural properties errors are skipped; nested paths run root to leaf", %{
      validator: validator
    } do
      issues =
        Validator.validate(validator, %{
          "serial_number" => "PX-2044",
          "condition" => "good",
          "nested" => %{"inner" => "x"}
        })

      assert [%Issue{code: :minLength, path: %InstancePath{segments: ["nested", "inner"]}}] =
               issues
    end

    test "a missing required property in a nested object lands at the nested path", %{
      validator: validator
    } do
      issues =
        Validator.validate(validator, %{
          "serial_number" => "PX-2044",
          "condition" => "good",
          "nested" => %{}
        })

      assert [%Issue{code: :required, path: %InstancePath{segments: ["nested", "inner"]}}] =
               issues
    end
  end
end
