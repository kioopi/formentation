defmodule Mix.Tasks.DemoTest do
  use ExUnit.Case, async: true

  doctest Mix.Tasks.Demo

  describe "parse_port/1" do
    test "defaults to 4000 when no argument is given" do
      assert Mix.Tasks.Demo.parse_port([]) == 4000
    end

    test "parses an explicit port argument" do
      assert Mix.Tasks.Demo.parse_port(["8080"]) == 8080
    end
  end

  describe "run/1" do
    test "raises a usage error when given too many arguments" do
      assert_raise Mix.Error, "usage: mix demo [port]", fn ->
        Mix.Tasks.Demo.run(["4000", "extra"])
      end
    end
  end

  describe "message/1" do
    test "announces both example URLs for the given port" do
      msg = Mix.Tasks.Demo.message(4000)

      assert msg =~ "http://localhost:4000"
      assert msg =~ "http://localhost:4000/nested"
    end
  end
end
