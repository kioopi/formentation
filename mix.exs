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
        "test.browser": :test,
        "test.dev": :test,
        # The task compiles on elixirc_paths(:test) so it stays out of the
        # published package.
        "vault.links": :test
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
      # Also in :test so `mix ci` (which runs in MIX_ENV=test) can gate on
      # `mix docs --warnings-as-errors`.
      {:ex_doc, "~> 0.38", only: [:dev, :test], runtime: false},
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
        "vault.links",
        "docs --warnings-as-errors",
        "test",
        "credo --strict",
        "dialyzer",
        "ex_dna --max-clones 0",
        "reach.check --arch --smells"
      ],
      "test.browser": [&test_browser/1]
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

  defp library_module?(module) do
    with true <- Code.ensure_loaded?(module),
         [_ | _] = source <- module.module_info(:compile)[:source] do
      source
      |> List.to_string()
      |> String.starts_with?(Path.join(File.cwd!(), "lib") <> "/")
    else
      _ -> false
    end
  end

  defp internal_documentation_module?(module) do
    # Two categories, one predicate. RenderPreparation and ReferenceComponents
    # are @moduledoc false and would be excluded anyway; they are listed for
    # grep-ability, and that is the convention — a new internal module gets
    # both @moduledoc false and an entry here. RenderPlan and the RenderNode.*
    # structs keep their moduledocs on purpose (`h Formentation.Phoenix.RenderPlan`
    # in IEx is supported), so this filter is the only thing keeping them out
    # of the published docs. The string prefix, rather than a list, covers
    # RenderNode.FieldDOM/GroupDOM and any future sibling without a list edit.
    module in [
      Formentation.Phoenix.ProjectedForm,
      Formentation.Phoenix.RenderPreparation,
      Formentation.Phoenix.ReferenceComponents,
      Formentation.Phoenix.RenderPlan,
      Formentation.Phoenix.RenderNode
    ] or String.starts_with?(Atom.to_string(module), "Elixir.Formentation.Phoenix.RenderNode.")
  end

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
      # Only the library itself is published API. `elixirc_paths/1` also
      # compiles `demo/` (:dev, :test) and `test/support/` (:test), and
      # `mix ci` runs `mix docs` in MIX_ENV=test — filtering on the compile
      # source keeps the gated doc surface equal to the published one.
      filter_modules: fn module, _metadata ->
        library_module?(module) and not internal_documentation_module?(module)
      end,
      groups_for_modules: [
        "Compile & query": [
          Formentation,
          Formentation.Definition,
          Formentation.Info,
          Formentation.Diagnostic
        ],
        "Nodes & paths": [
          Formentation.Semantic.Object,
          Formentation.Semantic.Field,
          Formentation.Semantic.Unsupported,
          Formentation.Presentation.Object,
          Formentation.Presentation.Field,
          Formentation.Presentation.Group,
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
          Formentation.Phoenix.DOMIdentity,
          Formentation.Phoenix.StateView,
          Formentation.Phoenix.StateView.Issue
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
