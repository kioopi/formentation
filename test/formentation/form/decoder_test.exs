defmodule Formentation.Form.DecoderTest do
  use ExUnit.Case, async: true

  alias Formentation.Form.Decoder
  alias Formentation.{InstancePath, Issue}

  doctest Formentation.Form.Decoder

  defp definition do
    {:ok, definition, []} =
      Formentation.compile(
        %{
          kind: :object,
          properties: [{"age", %{kind: :integer}}, {"name", %{kind: :string}}]
        },
        adapter: Formentation.Source.Map
      )

    definition
  end

  test "a provided decodable value yields its transport, a set operation, and no issues" do
    {transports, operations, issues} = Decoder.decode(definition(), %{"age" => "42"})

    age = InstancePath.new!(["age"])
    assert transports[age] == {:provided, "42"}
    assert operations[age] == {:set, 42}
    assert issues == %{}
  end

  test "an absent key yields :not_provided and :unset" do
    {transports, operations, _issues} = Decoder.decode(definition(), %{})

    name = InstancePath.new!(["name"])
    assert transports[name] == :not_provided
    assert operations[name] == :unset
  end

  test "an undecodable value yields an invalid operation and a decode issue at the path" do
    {transports, operations, issues} = Decoder.decode(definition(), %{"age" => "4x"})

    age = InstancePath.new!(["age"])
    assert transports[age] == {:provided, "4x"}
    assert {:invalid, %Issue{source: :decode, path: ^age}} = operations[age]
    assert [%Issue{source: :decode}] = issues[age]
  end
end
