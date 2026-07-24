defmodule Formentation.CodecTest do
  use ExUnit.Case, async: true

  alias Formentation.{Codec, InstancePath, Issue}

  doctest Formentation.Codec

  @path InstancePath.new!(["field"])

  describe "string" do
    test "preserves input verbatim, including empty and whitespace-only" do
      assert Codec.decode(:string, "hello", @path) == {:set, "hello"}
      assert Codec.decode(:string, "", @path) == {:set, ""}
      assert Codec.decode(:string, "  padded  ", @path) == {:set, "  padded  "}
    end

    test "rejects nil and non-binary values" do
      assert {:invalid, %Issue{code: :invalid_value, source: :decode, path: @path}} =
               Codec.decode(:string, nil, @path)

      assert {:invalid, %Issue{code: :invalid_value}} = Codec.decode(:string, %{}, @path)
    end
  end

  describe "integer" do
    test "parses full tokens after trimming surrounding whitespace" do
      assert Codec.decode(:integer, "12", @path) == {:set, 12}
      assert Codec.decode(:integer, " 12 ", @path) == {:set, 12}
      assert Codec.decode(:integer, "-7", @path) == {:set, -7}
      assert Codec.decode(:integer, "+7", @path) == {:set, 7}
      assert Codec.decode(:integer, "007", @path) == {:set, 7}
    end

    test "trimmed-empty input is an unset" do
      assert Codec.decode(:integer, "", @path) == :unset
      assert Codec.decode(:integer, "   ", @path) == :unset
    end

    test "rejects partial and non-integer tokens with the raw value in the message" do
      for raw <- ["12.0", "1e3", "0x10", "12a", "twelve"] do
        assert {:invalid, %Issue{code: :invalid_integer, source: :decode} = issue} =
                 Codec.decode(:integer, raw, @path)

        assert issue.message =~ inspect(raw)
      end
    end

    test "passes native integers through and rejects other native values" do
      assert Codec.decode(:integer, 42, @path) == {:set, 42}
      assert {:invalid, %Issue{code: :invalid_value}} = Codec.decode(:integer, 4.2, @path)
      assert {:invalid, %Issue{code: :invalid_value}} = Codec.decode(:integer, nil, @path)
    end
  end

  describe "number" do
    test "preserves integer-ness for plain integer tokens" do
      assert Codec.decode(:number, "12", @path) == {:set, 12}
      assert Codec.decode(:number, " -3 ", @path) == {:set, -3}
    end

    test "parses fractions and exponents as floats" do
      assert Codec.decode(:number, "12.5", @path) == {:set, 12.5}
      assert Codec.decode(:number, "-0.5", @path) == {:set, -0.5}
      assert Codec.decode(:number, "1e3", @path) == {:set, 1.0e3}
      assert Codec.decode(:number, "1.5E-2", @path) == {:set, 1.5e-2}
      assert Codec.decode(:number, "+2.5", @path) == {:set, 2.5}
      assert Codec.decode(:number, "-1e-3", @path) == {:set, -1.0e-3}
    end

    test "trimmed-empty input is an unset" do
      assert Codec.decode(:number, "", @path) == :unset
      assert Codec.decode(:number, " ", @path) == :unset
    end

    test "rejects non-number tokens" do
      for raw <- [".5", "12.", "1e", "12,5", "NaN", "abc"] do
        assert {:invalid, %Issue{code: :invalid_number, source: :decode} = issue} =
                 Codec.decode(:number, raw, @path)

        assert issue.message =~ inspect(raw)
      end
    end

    test "passes native integers and floats through" do
      assert Codec.decode(:number, 42, @path) == {:set, 42}
      assert Codec.decode(:number, 4.2, @path) == {:set, 4.2}
    end

    test "rejects native non-numbers" do
      assert {:invalid, %Issue{code: :invalid_value}} = Codec.decode(:number, true, @path)
      assert {:invalid, %Issue{code: :invalid_value}} = Codec.decode(:number, nil, @path)
    end
  end

  describe "boolean" do
    test "accepts exactly true and false after trimming (D-011 contract)" do
      assert Codec.decode(:boolean, "true", @path) == {:set, true}
      assert Codec.decode(:boolean, "false", @path) == {:set, false}
      assert Codec.decode(:boolean, " true ", @path) == {:set, true}
    end

    test "trimmed-empty input is an unset" do
      assert Codec.decode(:boolean, "", @path) == :unset
    end

    test "rejects everything else — never manufactures false" do
      for raw <- ["TRUE", "1", "0", "on", "yes"] do
        assert {:invalid, %Issue{code: :invalid_boolean, source: :decode}} =
                 Codec.decode(:boolean, raw, @path)
      end
    end

    test "passes native booleans through" do
      assert Codec.decode(:boolean, true, @path) == {:set, true}
      assert Codec.decode(:boolean, false, @path) == {:set, false}
    end
  end
end
