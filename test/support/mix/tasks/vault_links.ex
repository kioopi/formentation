defmodule Mix.Tasks.Vault.Links do
  @shortdoc "Fails on documentation wikilinks split across a line break"

  @moduledoc """
  Checks the Obsidian vault for `[[wikilinks]]` containing a line break.

  Obsidian does not parse a link that spans two lines — it renders as
  literal text — so re-wrapping a paragraph can silently destroy a link
  while every other check stays green. Running this as a `mix ci` step
  makes that a build failure instead of something a reviewer has to catch.

  Fenced blocks and inline code spans are skipped, so code samples and
  prose *about* wikilink syntax never trip the check.

  ## Usage

      mix vault.links [path]

  Defaults to `docs/Formentation`, the vault root. Only that tree is
  checked: `docs/discussion/` and `docs/superpowers/` are untracked
  working notes.

  The task compiles on `elixirc_paths(:test)` so it stays out of the
  published package, which is why `cli/0` runs it in `MIX_ENV=test`.
  """

  use Mix.Task

  @vault "docs/Formentation"

  @failure "Wikilinks split across a line break (Obsidian renders these as literal text):"

  @impl true
  def run(argv) do
    case argv |> vault_root() |> offenders() do
      [] ->
        Mix.shell().info("Vault wikilinks OK")
        :ok

      offenders ->
        Mix.raise(Enum.join([@failure | offenders], "\n"))
    end
  end

  @doc """
  Returns `{line_number, trimmed_line}` for every line of `content` that
  opens a wikilink it does not close.

  ## Examples

      iex> Mix.Tasks.Vault.Links.split_links("See [[a-note|the whole link]].")
      []

      iex> Mix.Tasks.Vault.Links.split_links("See [[a-note|the\\nnote]].")
      [{1, "See [[a-note|the"}]

  """
  @spec split_links(String.t()) :: [{pos_integer(), String.t()}]
  def split_links(content) do
    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce({[], false}, &scan_line/2)
    |> elem(0)
    |> Enum.reverse()
  end

  defp vault_root([]), do: @vault
  defp vault_root([path]), do: path
  defp vault_root(_argv), do: Mix.raise("usage: mix vault.links [path]")

  defp offenders(root) do
    root
    |> Path.join("**/*.md")
    |> Path.wildcard()
    |> Enum.flat_map(fn file ->
      file
      |> File.read!()
      |> split_links()
      |> Enum.map(fn {line, text} -> "  #{file}:#{line}: #{text}" end)
    end)
  end

  defp scan_line({text, line}, {found, fenced?}) do
    cond do
      String.starts_with?(String.trim_leading(text), "```") -> {found, not fenced?}
      fenced? -> {found, fenced?}
      opens_a_link?(text) -> {[{line, String.trim(text)} | found], fenced?}
      true -> {found, fenced?}
    end
  end

  # Inline code is stripped before counting so that a documented `[[`
  # is not mistaken for the start of a link.
  defp opens_a_link?(text) do
    prose = String.replace(text, ~r/`[^`]*`/, "")

    occurrences(prose, "[[") > occurrences(prose, "]]")
  end

  defp occurrences(text, pattern), do: length(String.split(text, pattern)) - 1
end
