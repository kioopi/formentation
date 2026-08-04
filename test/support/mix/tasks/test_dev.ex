defmodule Mix.Tasks.Test.Dev do
  @shortdoc "Formats the project, then runs the tests your change affects"

  @moduledoc """
  The development inner loop: `mix format` across the project, then
  `mix test`.

  With no target argument the run is narrowed with `--stale`, so only the
  tests affected by what you changed run. Naming a file, a line, or a
  directory runs exactly that instead — `mix test --stale some_test.exs`
  selects the intersection of "stale" and "that file", which is empty
  whenever the file is not itself stale, and reports "No stale tests"
  while exiting 0.

  Nothing here sets `PORT`: no part of this project reads it, and
  non-browser tests start the demo endpoint with `server: false`, binding
  no socket at all.

  ## Usage

      mix test.dev
      mix test.dev test/formentation/form_test.exs
      mix test.dev test/formentation/form_test.exs:42
      mix test.dev --max-failures 3
      mix test.dev --failed

  The browser-real suite is opt-in and separate; see `mix test.browser`.
  Run `mix ci` when the work is done.

  The task compiles on `elixirc_paths(:test)` so it stays out of the
  published package, which is why `cli/0` runs it in `MIX_ENV=test`.
  """

  use Mix.Task

  @impl true
  def run(argv) do
    Mix.Task.run("format", [])
    Mix.Task.run("test", test_args(argv))
  end

  @doc """
  Builds the `mix test` arguments for `argv`.

  Adds `--stale` when the caller named no test target, so a bare
  `mix test.dev` runs only what the change affects. When a target *is*
  named, `--stale` is left off, and an explicit `--stale` is never
  duplicated. `--failed` narrows the run on its own, exactly like a named
  target, so it is treated the same way — `mix test` refuses to combine
  `--failed` with `--stale` and raises if both are passed.

  ## Examples

      iex> Mix.Tasks.Test.Dev.test_args([])
      ["--stale"]

      iex> Mix.Tasks.Test.Dev.test_args(["--max-failures", "3"])
      ["--stale", "--max-failures", "3"]

      iex> Mix.Tasks.Test.Dev.test_args(["test/formentation/form_test.exs:42"])
      ["test/formentation/form_test.exs:42"]

      iex> Mix.Tasks.Test.Dev.test_args(["--stale"])
      ["--stale"]

      iex> Mix.Tasks.Test.Dev.test_args(["--failed"])
      ["--failed"]

  """
  @spec test_args([String.t()]) :: [String.t()]
  def test_args(argv) do
    if Enum.any?(argv, &(&1 in ["--stale", "--failed"])) or Enum.any?(argv, &target?/1) do
      argv
    else
      ["--stale" | argv]
    end
  end

  @doc """
  Returns true when `arg` names a test file, line, or directory rather
  than a switch or a switch's value.

  A bare "does not start with `-`" rule would read the `3` in
  `--max-failures 3` as a path and wrongly suppress `--stale`, so a
  target must also look like one: contain a `/`, end in `.exs` with any
  number of `:line` suffixes, or — for a bare word with neither, such as
  `test` — name a directory that actually exists. Misreading a switch's
  value as a target only costs an extra `--stale` that runs more tests;
  the reverse silently runs none, so the check is biased toward the
  filesystem call when in doubt.

  ## Examples

      iex> Mix.Tasks.Test.Dev.target?("test/formentation/form_test.exs")
      true

      iex> Mix.Tasks.Test.Dev.target?("form_test.exs:42:87")
      true

      iex> Mix.Tasks.Test.Dev.target?("--max-failures")
      false

      iex> Mix.Tasks.Test.Dev.target?("3")
      false

  """
  @spec target?(String.t()) :: boolean()
  def target?("-" <> _rest), do: false

  def target?(arg) do
    String.contains?(arg, "/") or Regex.match?(~r/\.exs(:\d+)*\z/, arg) or File.dir?(arg)
  end
end
