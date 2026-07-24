defmodule Formentation.TransportTest do
  use ExUnit.Case, async: true

  alias Formentation.{InstancePath, Transport}

  doctest Formentation.Transport

  defp path(segments), do: InstancePath.new!(segments)

  test "strips Phoenix metadata from domain params, recursively" do
    values = %{
      "title" => "New title",
      "email" => "",
      "_unused_email" => "",
      "_csrf_token" => "tok",
      "_target" => ["email"],
      "bday" => %{"day" => "", "_unused_day" => ""}
    }

    normalized = Transport.normalize(values)

    assert normalized.domain_params == %{
             "title" => "New title",
             "email" => "",
             "bday" => %{"day" => ""}
           }
  end

  test "preserves the Phoenix-compatible view byte for byte" do
    values = %{"email" => "", "_unused_email" => "", "_csrf_token" => "tok"}
    assert Transport.normalize(values).phoenix_params == values
  end

  test "extracts usage from unused markers" do
    normalized = Transport.normalize(%{"title" => "T", "email" => "", "_unused_email" => ""})

    assert normalized.usage == %{
             path(["title"]) => :used,
             path(["email"]) => :unused
           }
  end

  test "propagates usage to parents: used when any descendant is used" do
    values = %{
      "bday" => %{
        "year" => "1990",
        "month" => "",
        "day" => "",
        "_unused_day" => ""
      }
    }

    normalized = Transport.normalize(values)

    assert normalized.usage == %{
             path(["bday"]) => :used,
             path(["bday", "year"]) => :used,
             path(["bday", "month"]) => :used,
             path(["bday", "day"]) => :unused
           }
  end

  test "a parent with only unused descendants is unused" do
    values = %{"bday" => %{"day" => "", "_unused_day" => ""}}

    assert Transport.normalize(values).usage == %{
             path(["bday"]) => :unused,
             path(["bday", "day"]) => :unused
           }
  end

  test "no markers at all produce plain used entries, never fabricated unused" do
    assert Transport.normalize(%{"title" => "T"}).usage == %{path(["title"]) => :used}
  end

  test "metadata keys get no usage entries" do
    normalized = Transport.normalize(%{"_csrf_token" => "tok", "_unused_email" => ""})
    assert normalized.usage == %{}
    assert normalized.domain_params == %{}
  end

  test "rejects non-string keys" do
    assert_raise ArgumentError, fn -> Transport.normalize(%{title: "T"}) end
  end

  test "metadata values are carried verbatim, never inspected" do
    values = %{"x" => "v", "_unused_x" => %{bad_key: 1}}
    normalized = Transport.normalize(values)

    assert normalized.domain_params == %{"x" => "v"}
    assert normalized.phoenix_params == values
    assert normalized.usage == %{path(["x"]) => :unused}
  end

  test "an empty nested map follows the marker convention like a leaf" do
    assert Transport.normalize(%{"group" => %{}}).usage == %{path(["group"]) => :used}

    assert Transport.normalize(%{"group" => %{}, "_unused_group" => ""}).usage ==
             %{path(["group"]) => :unused}
  end

  test "_persistent_id is metadata: stripped at every level, no usage entry, preserved for Phoenix" do
    n =
      Transport.normalize(%{
        "_persistent_id" => "0",
        "name" => "Ada",
        "address" => %{"_persistent_id" => "1", "street" => "Main"}
      })

    assert n.domain_params == %{"name" => "Ada", "address" => %{"street" => "Main"}}

    refute Enum.any?(Map.keys(n.usage), fn path -> "_persistent_id" in path.segments end)

    assert n.phoenix_params["_persistent_id"] == "0"
    assert n.phoenix_params["address"]["_persistent_id"] == "1"
  end
end
