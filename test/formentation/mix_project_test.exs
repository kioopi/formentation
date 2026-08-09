defmodule Formentation.MixProjectTest do
  use ExUnit.Case, async: true

  # Formentation is a library: every unconditional, non-optional dependency it
  # declares is imposed on every consuming application, so the set is part of
  # the public contract and README documents it by name. This test is the
  # invariant behind that promise — a UI library, a tooling helper, or a
  # convenience wrapper added without `only:`/`runtime: false`/`optional: true`
  # fails here rather than quietly landing in every consumer's build.
  #
  # See https://github.com/kioopi/formentation/issues/9.
  @documented_runtime_deps [:jsv, :phoenix_html, :phoenix_live_view]

  describe "declared dependencies" do
    test "the unconditional runtime set is exactly the set README documents" do
      assert runtime_deps() == @documented_runtime_deps
    end
  end

  defp runtime_deps do
    Mix.Project.config()
    |> Keyword.fetch!(:deps)
    |> Enum.filter(&runtime_dep?/1)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
  end

  # A dependency reaches a consumer's runtime unless it is env-scoped
  # (`only:`), build-only (`runtime: false`), or opt-in (`optional: true`).
  defp runtime_dep?(dep) do
    opts = dep_opts(dep)

    is_nil(opts[:only]) and opts[:runtime] != false and opts[:optional] != true
  end

  defp dep_opts({_name, opts}) when is_list(opts), do: opts
  defp dep_opts({_name, _requirement}), do: []
  defp dep_opts({_name, _requirement, opts}), do: opts
end
