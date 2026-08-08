defmodule Formentation.FormPropertyTest do
  # async: false — the atom-count assertion measures the global VM atom
  # table, which would otherwise race against atoms allocated by
  # concurrently running async test suites.
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Formentation.Fixtures.PumpInspection
  alias Formentation.Form
  alias Formentation.Form.Params

  defp pump_definition do
    {:ok, definition, []} =
      Formentation.compile(PumpInspection.map_source(),
        adapter: Formentation.Source.Map
      )

    definition
  end

  defp text, do: StreamData.string(:printable, max_length: 12)

  defp integer_ish do
    StreamData.one_of([
      text(),
      StreamData.constant(""),
      StreamData.map(StreamData.integer(-999..999), &Integer.to_string/1)
    ])
  end

  defp number_ish do
    StreamData.one_of([
      text(),
      StreamData.map(StreamData.integer(-999..999), &Integer.to_string/1),
      StreamData.map(StreamData.float(min: -100.0, max: 100.0), &Float.to_string/1)
    ])
  end

  defp boolean_ish do
    StreamData.one_of([
      text(),
      StreamData.constant("true"),
      StreamData.constant("false")
    ])
  end

  defp pump_values do
    StreamData.optional_map(%{
      "serial_number" => text(),
      "condition" => text(),
      "operating_hours" => integer_ish(),
      "voltage" => number_ish(),
      "insulation_ok" => boolean_ish(),
      "notes" => text()
    })
  end

  property "replace transitions are idempotent" do
    definition = pump_definition()

    check all(values <- pump_values()) do
      envelope = %Params{values: values}
      once = Form.transition(Form.new(definition), envelope)
      twice = Form.transition(once, envelope)

      assert twice == once
    end
  end

  property "the candidate never contains a raw undecodable value" do
    definition = pump_definition()

    check all(values <- pump_values()) do
      form = Form.transition(Form.new(definition), %Params{values: values})

      case Form.candidate(form) do
        :none ->
          assert Enum.any?(form.operations, fn {_p, op} -> match?({:invalid, _}, op) end)

        {:ok, candidate} ->
          for {key, typed?} <- [
                {"operating_hours", &is_integer/1},
                {"voltage", &is_number/1},
                {"insulation_ok", &is_boolean/1}
              ] do
            case Map.fetch(candidate, key) do
              {:ok, value} -> assert typed?.(value)
              :error -> :ok
            end
          end
      end
    end
  end

  # Asserts a language guarantee (no aliasing in the BEAM) as an explicit
  # statement of intent — it cannot fail today; it documents the contract.
  property "transitions never mutate the input form" do
    definition = pump_definition()

    check all(values <- pump_values()) do
      form = Form.new(definition, %{"notes" => "original"})
      snapshot = form
      _next = Form.transition(form, %Params{values: values})

      assert form == snapshot
    end
  end

  property "transitions create no atoms from params keys" do
    definition = pump_definition()
    form = Form.new(definition)

    # Warm up all code paths so lazily-loaded modules do not skew the count.
    _ = Form.transition(form, %Params{values: %{"warmup" => "x"}})

    before = :erlang.system_info(:atom_count)

    check all(
            keys <-
              StreamData.list_of(StreamData.string(:alphanumeric, min_length: 1), max_length: 6)
          ) do
      values = Map.new(keys, fn key -> {"k_" <> key, "value"} end)
      _ = Form.transition(form, %Params{values: values})

      assert :erlang.system_info(:atom_count) == before
    end
  end

  describe "read-only preservation (D-016)" do
    defp read_only_definition do
      declaration = %{
        kind: :object,
        properties: [
          {"serial_number", %{kind: :string, read_only: true}},
          {"location", %{kind: :string}}
        ]
      }

      {:ok, definition, []} =
        Formentation.compile(declaration, adapter: Formentation.Source.Map)

      definition
    end

    property "the candidate at read-only paths equals original data at those paths" do
      check all(
              original_serial <- StreamData.one_of([StreamData.constant(:absent), text()]),
              values <-
                StreamData.optional_map(%{
                  "serial_number" => text(),
                  "location" => text()
                })
            ) do
        original =
          case original_serial do
            :absent -> %{}
            value -> %{"serial_number" => value}
          end

        form = Form.new(read_only_definition(), original)
        form = Form.transition(form, %Params{values: values})

        assert {:ok, candidate} = Form.candidate(form)
        assert Map.fetch(candidate, "serial_number") == Map.fetch(original, "serial_number")
      end
    end
  end
end
