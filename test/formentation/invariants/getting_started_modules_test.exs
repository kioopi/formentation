defmodule Formentation.GettingStartedModulesTest do
  use ExUnit.Case, async: true

  # Getting started is the page a new user reads first, and its cost is
  # measured in nouns: every fully qualified module named there is one
  # more concept standing between the reader and a working form. The
  # north-star contract fixes that budget at four
  # (https://github.com/kioopi/formentation/issues/46, Wave 4 §3).
  #
  # What this scans: the whole file, raw — frontmatter, prose, code
  # fences, and wikilinks alike. It extracts `Formentation` followed by
  # dot-separated capitalized segments, so `Formentation.form/2` counts
  # as `Formentation` and `Formentation.Info.fields/1` counts as
  # `Formentation.Info`. It is deliberately not a Markdown parser: a
  # module name a reader can see anywhere on the page is a name the page
  # spends, wherever it appears.
  #
  # The page is tracked as an external resource *and* read at compile
  # time, for the reason `Formentation.FixtureTrackingTest` documents:
  # either half alone leaves `mix test --stale` — what `mix test.dev`
  # runs — selecting zero tests when only the page changed, which is
  # exactly the edit this guardrail exists to catch.
  @page Path.expand("../../../docs/Formentation/Userguide/getting-started.md", __DIR__)
  @external_resource @page
  @source File.read!(@page)

  @approved MapSet.new([
              "Formentation",
              "Formentation.Definition",
              "Formentation.Form",
              "Formentation.Phoenix"
            ])

  test "getting started names only the four agreed Formentation modules" do
    named =
      ~r/Formentation(?:\.[A-Z][A-Za-z0-9_]*)*/
      |> Regex.scan(@source)
      |> List.flatten()
      |> MapSet.new()

    extra = named |> MapSet.difference(@approved) |> MapSet.to_list() |> Enum.sort()

    assert extra == []
  end
end
