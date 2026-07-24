defmodule PackagingTest do
  use ExUnit.Case, async: true

  @license Path.expand("../LICENSE", __DIR__)

  describe "LICENSE file" do
    test "exists at the project root" do
      assert File.exists?(@license)
    end

    test "is the MIT license naming the copyright holder" do
      contents = File.read!(@license)
      assert contents =~ "MIT License"
      assert contents =~ "Copyright (c) 2026 Vangelis Tsoumenis"
    end
  end

  describe "mix.exs packaging metadata" do
    setup do
      %{project: Formentation.MixProject.project()}
    end

    test "declares version 0.1.0", %{project: project} do
      assert project[:version] == "0.1.0"
    end

    test "carries the one-line description", %{project: project} do
      assert project[:description] == "Declarative forms from JSON Schema or Elixir data."
    end

    test "points source_url at the GitHub repo", %{project: project} do
      assert project[:source_url] == "https://github.com/kioopi/formentation"
    end

    test "declares the MIT license and a GitHub link", %{project: project} do
      package = project[:package]
      assert package[:licenses] == ["MIT"]
      assert package[:links] == %{"GitHub" => "https://github.com/kioopi/formentation"}
    end

    test "ships a LICENSE file for every declared license", %{project: project} do
      assert project[:package][:licenses] == ["MIT"]
      assert File.exists?(Path.expand("../LICENSE", __DIR__))
    end
  end
end
