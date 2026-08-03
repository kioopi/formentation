defmodule Formentation.Phoenix.DOMIdentityTest do
  use ExUnit.Case, async: true

  alias Formentation.InstancePath
  alias Formentation.Phoenix.DOMIdentity

  @namespace "asset_payload"

  describe "documented ID spelling" do
    test "encodes field parts without suffix ambiguity" do
      assert DOMIdentity.field(@namespace, path(["serial_number"]), :control) ==
               "ftn--asset_payload--field--control--serial_number"

      assert DOMIdentity.field(@namespace, path(["notes"]), :help) ==
               "ftn--asset_payload--field--help--notes"

      assert DOMIdentity.field(@namespace, path(["notes"]), :errors) ==
               "ftn--asset_payload--field--errors--notes"

      assert DOMIdentity.field(@namespace, path(["notes_help"]), :control) ==
               "ftn--asset_payload--field--control--notes_help"

      assert DOMIdentity.field(@namespace, path(["notes_errors"]), :control) ==
               "ftn--asset_payload--field--control--notes_errors"
    end

    test "preserves path boundaries and segment types" do
      assert DOMIdentity.field(@namespace, path(["a_b"]), :control) ==
               "ftn--asset_payload--field--control--a_b"

      assert DOMIdentity.field(@namespace, path(["a", "b"]), :control) ==
               "ftn--asset_payload--field--control--a--b"

      assert DOMIdentity.field(@namespace, path(["addresses", 0, "street"]), :control) ==
               "ftn--asset_payload--field--control--addresses--0--street"

      assert DOMIdentity.field(@namespace, path(["addresses", "0"]), :control) ==
               "ftn--asset_payload--field--control--addresses---30"
    end

    test "encodes radio option parts and readable hostile strings" do
      assert DOMIdentity.field(@namespace, path(["condition"]), {:option, 2}) ==
               "ftn--asset_payload--field--option_2--condition"

      assert DOMIdentity.field(@namespace, path(["serial-number"]), :control) ==
               "ftn--asset_payload--field--control--serial-2Dnumber"

      assert DOMIdentity.field(@namespace, path(["straße"]), :control) ==
               "ftn--asset_payload--field--control--stra-C3-9Fe"

      assert DOMIdentity.field(@namespace, path(["a--b"]), :control) ==
               "ftn--asset_payload--field--control--a-2D-2Db"
    end

    test "distinguishes objects and occurrence-scoped groups" do
      assert DOMIdentity.object(@namespace, path([]), :container) ==
               "ftn--asset_payload--object--container"

      assert DOMIdentity.object(@namespace, path(["address"]), :container) ==
               "ftn--asset_payload--object--container--address"

      assert DOMIdentity.group(@namespace, "/#electrical", path([]), :container) ==
               "ftn--asset_payload--group--container---2F-23electrical"
    end
  end

  describe "input validation" do
    test "rejects missing or invalid namespaces" do
      for namespace <- [nil, "", :payload] do
        assert_raise ArgumentError, ~r/non-empty binary namespace/, fn ->
          DOMIdentity.field(namespace, path(["email"]), :control)
        end
      end
    end

    test "rejects unsupported parts" do
      assert_raise ArgumentError, ~r/invalid field DOM identity part/, fn ->
        DOMIdentity.field(@namespace, path(["email"]), :container)
      end

      assert_raise ArgumentError, ~r/invalid group DOM identity part/, fn ->
        DOMIdentity.group(@namespace, "/#details", path([]), :errors)
      end
    end
  end

  defp path(segments), do: InstancePath.new!(segments)
end
