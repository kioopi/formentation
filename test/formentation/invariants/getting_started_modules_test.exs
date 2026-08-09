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

  @own_source File.read!(__ENV__.file)

  @approved MapSet.new([
              "Formentation",
              "Formentation.Definition",
              "Formentation.Form",
              "Formentation.Phoenix"
            ])

  test "getting started names exactly the four agreed Formentation modules" do
    named =
      ~r/Formentation(?:\.[A-Z][A-Za-z0-9_]*)*/
      |> Regex.scan(@source)
      |> List.flatten()
      |> MapSet.new()

    # The contract is "exactly", not "at most". A page that stopped
    # naming `Formentation.Form` would still be within budget while no
    # longer teaching the lifecycle, so absence is as much a violation
    # as excess.
    missing = @approved |> MapSet.difference(named) |> MapSet.to_list() |> Enum.sort()
    extra = named |> MapSet.difference(@approved) |> MapSet.to_list() |> Enum.sort()

    assert missing == [], "Getting started no longer names: #{inspect(missing)}"
    assert extra == [], "Getting started names unapproved modules: #{inspect(extra)}"
  end

  # Self-contained, because a cross-module assertion would depend on
  # another test module being loaded: running this file alone, or having
  # `--stale` select only the sibling, would raise UndefinedFunctionError
  # rather than report a real result.
  #
  # Both halves are pinned for the reason `Formentation.FixtureTrackingTest`
  # documents for fixtures. Without `@external_resource` a page edit marks
  # nothing stale; with it but a runtime read in a function body the
  # recompiled `.beam` is byte-identical, so `mix test --stale` — what
  # `mix test.dev` runs — still selects nothing and reports a green that
  # proves nothing.
  test "the page is tracked and read at compile time, so editing it selects this test" do
    tracked =
      __MODULE__.module_info(:attributes)
      |> Keyword.get_values(:external_resource)
      |> List.flatten()
      |> Enum.map(&to_string/1)

    assert @page in tracked

    assert @own_source =~ "@source File.read!(@page)",
           "the page must be read into a module attribute at compile time, " <>
             "not inside a function body"
  end
end
