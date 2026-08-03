defmodule Formentation.Phoenix.DOMIdentityTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  doctest Formentation.Phoenix.DOMIdentity

  alias Formentation.InstancePath
  alias Formentation.Phoenix.DOMIdentity
  alias Formentation.Phoenix.DOMIdentityDecoder

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
      assert DOMIdentity.field(@namespace, path(["condition"]), :container) ==
               "ftn--asset_payload--field--container--condition"

      assert DOMIdentity.field(@namespace, path(["condition"]), {:option, 2}) ==
               "ftn--asset_payload--field--option_2--condition"

      assert DOMIdentity.field(@namespace, path(["condition"]), {:option, 0}) ==
               "ftn--asset_payload--field--option_0--condition"

      assert DOMIdentity.field(@namespace, path(["condition"]), {:option, 10}) ==
               "ftn--asset_payload--field--option_10--condition"

      assert DOMIdentity.field(@namespace, path(["serial-number"]), :control) ==
               "ftn--asset_payload--field--control--serial-2Dnumber"

      assert DOMIdentity.field(@namespace, path(["straße"]), :control) ==
               "ftn--asset_payload--field--control--stra-C3-9Fe"

      assert DOMIdentity.field(@namespace, path(["a--b"]), :control) ==
               "ftn--asset_payload--field--control--a-2D-2Db"

      assert DOMIdentity.field(@namespace, path(["first name"]), :control) ==
               "ftn--asset_payload--field--control--first-20name"
    end

    test "distinguishes objects and occurrence-scoped groups" do
      assert DOMIdentity.object(@namespace, path([]), :container) ==
               "ftn--asset_payload--object--container"

      assert DOMIdentity.object(@namespace, path(["address"]), :container) ==
               "ftn--asset_payload--object--container--address"

      assert DOMIdentity.group(@namespace, "/#electrical", path([]), :container) ==
               "ftn--asset_payload--group--container---2F-23electrical"

      assert DOMIdentity.group(@namespace, "/#electrical", path(["addresses", 0]), :container) ==
               "ftn--asset_payload--group--container---2F-23electrical--addresses--0"

      assert DOMIdentity.group(@namespace, "/#electrical", path(["addresses", 1]), :container) ==
               "ftn--asset_payload--group--container---2F-23electrical--addresses--1"
    end

    test "pins empty, leading-digit, and escape boundaries" do
      assert DOMIdentity.field(@namespace, path(["0abc"]), :control) ==
               "ftn--asset_payload--field--control---30abc"

      assert DOMIdentity.field(@namespace, path([""]), :control) ==
               "ftn--asset_payload--field--control--"

      assert DOMIdentity.field(@namespace, path(["-"]), :control) ==
               "ftn--asset_payload--field--control---2D"

      assert DOMIdentity.field(@namespace, path(["-start"]), :control) ==
               "ftn--asset_payload--field--control---2Dstart"

      assert DOMIdentity.field(@namespace, path(["end-"]), :control) ==
               "ftn--asset_payload--field--control--end-2D"

      assert DOMIdentity.field("asset-form_", path(["notes"]), :control) ==
               "ftn--asset-2Dform_--field--control--notes"

      assert DOMIdentity.group(@namespace, "/a~0b~1c~2d", path([]), :container) ==
               "ftn--asset_payload--group--container---2Fa-7E0b-7E1c-7E2d"
    end
  end

  describe "test decoder" do
    test "funnels malformed ids through one actionable error" do
      for id <- [
            "ftn----field--control--x",
            "ftn--ns--field--legend--x",
            "ftn--ns--object--errors",
            "ftn--ns--field--option_--x",
            "ftn--ns--field--option_007--x",
            "ftn--ns--field--option_+1--x",
            "ftn--ns--field--control--a-"
          ] do
        error = assert_raise ArgumentError, fn -> DOMIdentityDecoder.decode(id) end
        assert error.message == "invalid DOM identity: #{inspect(id)}"
      end
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
        DOMIdentity.field(@namespace, path(["email"]), :legend)
      end

      assert_raise ArgumentError, ~r/invalid group DOM identity part/, fn ->
        DOMIdentity.group(@namespace, "/#details", path([]), :errors)
      end
    end

    test "reports invalid layout ids accurately" do
      assert_raise ArgumentError, ~r/layout id must be a binary/, fn ->
        DOMIdentity.group(@namespace, :details, path([]), :container)
      end
    end
  end

  property "round-trips hostile typed identities without collisions" do
    check all(
            identities <- StreamData.uniq_list_of(identity_gen(), min_length: 2, max_length: 20)
          ) do
      ids = Enum.map(identities, &encode/1)

      assert Enum.map(ids, &DOMIdentityDecoder.decode/1) == identities
      assert Enum.uniq(ids) == ids
      assert Enum.all?(ids, &String.starts_with?(&1, "ftn--"))
      assert Enum.all?(ids, &Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, &1))
    end
  end

  property "is deterministic and namespaces domain-separate the same identity" do
    check all(
            identity <- identity_gen(),
            namespace <- namespace_gen(),
            other <- namespace_gen(),
            namespace != other
          ) do
      assert encode(identity) == encode(identity)
      refute encode(identity, namespace) == encode(identity, other)
    end
  end

  defp identity_gen do
    StreamData.one_of([
      StreamData.map({namespace_gen(), path_gen(), field_part_gen()}, fn {namespace, path, part} ->
        {:field, namespace, path, part}
      end),
      StreamData.map({namespace_gen(), path_gen(), container_part_gen()}, fn {namespace, path,
                                                                              part} ->
        {:object, namespace, path, part}
      end),
      StreamData.map(
        {namespace_gen(), hostile_string_gen(), path_gen(), container_part_gen()},
        fn {namespace, layout_id, path, part} ->
          {:group, namespace, layout_id, path, part}
        end
      )
    ])
  end

  defp namespace_gen do
    hostile_string_gen()
    |> StreamData.filter(&(&1 != ""))
  end

  defp path_gen do
    StreamData.list_of(
      StreamData.one_of([hostile_string_gen(), StreamData.integer(0..100)]),
      max_length: 5
    )
    |> StreamData.map(&path/1)
  end

  defp field_part_gen do
    StreamData.one_of([
      StreamData.member_of([:control, :container, :help, :errors]),
      StreamData.map(StreamData.integer(0..20), &{:option, &1})
    ])
  end

  defp container_part_gen, do: StreamData.member_of([:container, :help])

  defp hostile_string_gen do
    StreamData.list_of(
      StreamData.member_of([?a, ?Z, ?0, ?_, ?-, ?#, ?/, ?~, ?\s, ?[, ?], 0x00DF, 0x4E2D]),
      max_length: 8
    )
    |> StreamData.map(&List.to_string/1)
  end

  defp encode({:field, namespace, path, part}), do: DOMIdentity.field(namespace, path, part)

  defp encode({:object, namespace, path, part}), do: DOMIdentity.object(namespace, path, part)

  defp encode({:group, namespace, layout_id, path, part}),
    do: DOMIdentity.group(namespace, layout_id, path, part)

  defp encode(identity, namespace) do
    case identity do
      {:field, _old_namespace, path, part} ->
        DOMIdentity.field(namespace, path, part)

      {:object, _old_namespace, path, part} ->
        DOMIdentity.object(namespace, path, part)

      {:group, _old_namespace, layout_id, path, part} ->
        DOMIdentity.group(namespace, layout_id, path, part)
    end
  end

  defp path(segments), do: InstancePath.new!(segments)
end
