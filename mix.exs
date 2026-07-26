defmodule Formentation.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/kioopi/formentation"

  def project do
    [
      app: :formentation,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: "Declarative forms from JSON Schema or Elixir data.",
      source_url: @source_url,
      package: package(),
      dialyzer: [plt_add_apps: [:ex_unit, :mix]],
      aliases: aliases(),
      test_coverage: [tool: Six],
      usage_rules: usage_rules(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [
        ci: :test,
        six: :test,
        "six.detail": :test,
        "six.html": :test,
        "test.browser": :test
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:usage_rules, "~> 1.0", only: [:dev]},
      {:jsv, "~> 0.21"},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.0", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:six, "~> 0.4", only: :test, runtime: false},
      {:vibe_kit, "~> 0.1"},
      {:stream_data, "~> 1.1", only: [:dev, :test]},
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:phoenix_html, "~> 4.2"},
      {:phoenix_live_view, "~> 1.1"},
      {:floki, "~> 0.38", only: :test},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:igniter, "~> 0.6", optional: true},
      {:bandit, "~> 1.0", only: [:dev, :test]},
      {:phoenix_test_playwright, "~> 0.14", only: :test, runtime: false}
    ]
  end

  defp aliases() do
    [
      ci: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        &check_vault_links/1,
        "test",
        "credo --strict",
        "dialyzer",
        "ex_dna --max-clones 0",
        "reach.check --arch --smells"
      ],
      "test.browser": [&test_browser/1],
      "vault.links": [&check_vault_links/1]
    ]
  end

  # `mix cmd PLAYWRIGHT_E2E=1 ...` doesn't set the env var: since Elixir 1.19,
  # `mix cmd` no longer shells out, so `PLAYWRIGHT_E2E=1` is treated as a
  # (nonexistent) executable rather than an assignment. Set the env var
  # directly and delegate to `mix test` in-process instead.
  defp test_browser(args) do
    System.put_env("PLAYWRIGHT_E2E", "1")
    Mix.Task.run("test", ["--only", "browser" | args])
  end

  @vault "docs/Formentation"

  # Obsidian does not parse a `[[wikilink]]` containing a line break: a
  # hard-wrapped link silently renders as literal text, so the note loses a
  # link without anything failing. Reflowing a paragraph is enough to
  # introduce one, which makes it a lint rather than a review habit.
  defp check_vault_links(_args) do
    case Enum.flat_map(Path.wildcard("#{@vault}/**/*.md"), &split_wikilinks/1) do
      [] ->
        Mix.shell().info("Vault wikilinks OK")

      offenders ->
        Mix.raise(
          "Wikilinks split across a line break (Obsidian renders these as literal text):\n" <>
            Enum.map_join(offenders, "\n", fn {file, line, text} ->
              "  #{file}:#{line}: #{text}"
            end)
        )
    end
  end

  # A line that opens more links than it closes continues one onto the next
  # line. Fenced blocks and inline code spans are ignored so that code and
  # prose *about* wikilink syntax are not mistaken for links.
  defp split_wikilinks(file) do
    file
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce({[], false}, &scan_line/2)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.map(fn {line, text} -> {file, line, text} end)
  end

  defp scan_line({text, line}, {found, fenced?}) do
    cond do
      String.starts_with?(String.trim_leading(text), "```") ->
        {found, not fenced?}

      fenced? ->
        {found, fenced?}

      opens_a_link?(text) ->
        {[{line, String.trim(text)} | found], fenced?}

      true ->
        {found, fenced?}
    end
  end

  defp opens_a_link?(text) do
    prose = String.replace(text, ~r/`[^`]*`/, "")
    occurrences(prose, "[[") > occurrences(prose, "]]")
  end

  defp occurrences(text, pattern), do: length(String.split(text, pattern)) - 1

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "Formentation",
      source_url: @source_url,
      source_ref: "v#{@version}",
      filter_modules: fn module, _metadata ->
        name = Atom.to_string(module)

        not String.starts_with?(name, "Elixir.FormentationDemo") and
          name != "Elixir.Mix.Tasks.Demo"
      end,
      groups_for_modules: [
        "Compile & query": [
          Formentation,
          Formentation.Definition,
          Formentation.Info,
          Formentation.Diagnostic
        ],
        "Nodes & paths": [
          Formentation.Node,
          Formentation.Node.Field,
          Formentation.Node.Group,
          Formentation.Node.Unsupported,
          Formentation.NodeId,
          Formentation.InstancePath,
          Formentation.TemplatePath,
          Formentation.JSONPointer
        ],
        "Form runtime": [
          Formentation.Form,
          Formentation.Form.FieldState,
          Formentation.Params,
          Formentation.Issue,
          Formentation.Codec,
          Formentation.Transport
        ],
        "Phoenix rendering": [
          Formentation.Phoenix,
          Formentation.Phoenix.Projector,
          Formentation.Phoenix.RenderPlan,
          Formentation.Phoenix.RenderNode,
          Formentation.Phoenix.RenderNode.Field,
          Formentation.Phoenix.RenderNode.Group,
          Formentation.Phoenix.Theme.Reference
        ],
        Sources: [
          Formentation.Source,
          Formentation.Source.Map,
          Formentation.JSONSchema,
          Formentation.JSONSchema.Validator
        ]
      ]
    ]
  end

  defp usage_rules do
    [
      file: "CLAUDE.md",
      usage_rules: ["usage_rules:all"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support", "demo"]
  defp elixirc_paths(:dev), do: ["lib", "demo"]
  defp elixirc_paths(_env), do: ["lib"]
end
