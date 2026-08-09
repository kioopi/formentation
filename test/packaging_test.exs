defmodule PackagingTest do
  use ExUnit.Case, async: true

  @license Path.expand("../LICENSE", __DIR__)

  # Tracked as external resources and read at compile time, for the reason
  # `Formentation.FixtureTrackingTest` documents: with a runtime read, editing
  # README's install line marks nothing stale and `mix test --stale` — what
  # `mix test.dev` runs — reports a green that proves nothing.
  @readme Path.expand("../README.md", __DIR__)
  @getting_started Path.expand("../docs/Formentation/Userguide/getting-started.md", __DIR__)

  @external_resource @readme
  @external_resource @getting_started

  @install_docs [
    {"README.md", File.read!(@readme)},
    {"docs/Formentation/Userguide/getting-started.md", File.read!(@getting_started)}
  ]

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

    test "declares version 0.2.0", %{project: project} do
      assert project[:version] == "0.2.0"
    end

    # Formentation installs from a Git tag, so the version in mix.exs and the
    # tag our documentation tells people to pin are the same fact written in
    # three places. Asserting the two documents against `project[:version]`
    # rather than a literal is what makes a future bump fail here instead of
    # shipping instructions that install the previous release.
    test "the documented install tag tracks the declared version", %{project: project} do
      expected = ~s(tag: "v#{project[:version]}")

      for {path, contents} <- @install_docs do
        assert contents =~ expected, "#{path} does not pin #{expected}"
      end
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
