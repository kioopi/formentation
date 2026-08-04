defmodule Mix.Tasks.Test.DevTest do
  use ExUnit.Case, async: true

  doctest Mix.Tasks.Test.Dev

  alias Mix.Tasks.Test.Dev

  describe "test_args/1" do
    test "narrows a bare run with --stale" do
      assert Dev.test_args([]) == ["--stale"]
    end

    test "keeps --stale in front of switches that name no target" do
      assert Dev.test_args(["--max-failures", "3"]) == ["--stale", "--max-failures", "3"]
      assert Dev.test_args(["--only", "browser"]) == ["--stale", "--only", "browser"]
    end

    test "omits --stale when a target is named, since the two intersect to nothing" do
      assert Dev.test_args(["test/formentation/form_test.exs"]) ==
               ["test/formentation/form_test.exs"]

      assert Dev.test_args(["test/formentation/form_test.exs:42"]) ==
               ["test/formentation/form_test.exs:42"]

      assert Dev.test_args(["test/formentation/"]) == ["test/formentation/"]
    end

    test "omits --stale when the target is a bare existing directory name" do
      assert Dev.test_args(["test"]) == ["test"]
    end

    test "omits --stale when a target is mixed in with switches" do
      assert Dev.test_args(["--max-failures", "1", "test/formentation/form_test.exs"]) ==
               ["--max-failures", "1", "test/formentation/form_test.exs"]
    end

    test "does not duplicate an explicit --stale" do
      assert Dev.test_args(["--stale"]) == ["--stale"]
      assert Dev.test_args(["--stale", "--trace"]) == ["--stale", "--trace"]
    end

    test "omits --stale for --failed, since mix test refuses to combine them" do
      assert Dev.test_args(["--failed"]) == ["--failed"]
      assert Dev.test_args(["--failed", "--trace"]) == ["--failed", "--trace"]
    end
  end

  describe "target?/1" do
    test "a switch value that looks numeric is not a target" do
      refute Dev.target?("3")
    end

    test "a switch value that looks like a word is not a target" do
      refute Dev.target?("browser")
      refute Dev.target?("ExUnit.CLIFormatter")
    end

    test "switches are not targets" do
      refute Dev.target?("--max-failures")
      refute Dev.target?("-t")
    end

    test "paths and .exs files with optional line numbers are targets" do
      assert Dev.target?("test/formentation/form_test.exs")
      assert Dev.target?("form_test.exs")
      assert Dev.target?("form_test.exs:42")
      assert Dev.target?("form_test.exs:42:87")
      assert Dev.target?("test/formentation/")
    end

    test "a bare word naming an existing directory is a target" do
      assert Dev.target?("test")
      refute Dev.target?("browser")
    end
  end
end
