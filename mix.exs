defmodule Muex.MixProject do
  use Mix.Project

  @app :muex
  @version "0.9.1"
  @source_url "https://github.com/Oeditus/muex"

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() not in [:dev, :test],
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      aliases: aliases(),
      escript: escript(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_file: {:no_warn, ".dialyzer/dialyzer.plt"},
        plt_add_deps: :app_tree,
        plt_add_apps: [:mix],
        plt_core_path: ".dialyzer",
        list_unused_filters: true,
        ignore_warnings: ".dialyzer/ignore.exs"
      ],
      name: "Muex",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger, :syntax_tools, :tools],
      mod: {Muex.Application, []}
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
    ]
  end

  def escript do
    [
      main_module: Muex.CLI,
      name: "muex",
      embed_elixir: true,
      app: nil
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:ci), do: ["lib"]
  defp elixirc_paths(:dev), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Core dependency
      {:jason, "~> 1.4"},

      # Development and documentation
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      quality: ["format", "credo --strict", "dialyzer"],
      "quality.ci": [
        "format --check-formatted",
        "credo --strict",
        "dialyzer"
      ]
    ]
  end

  defp description do
    """
    Language-agnostic mutation testing library for Elixir, Erlang, and other BEAM languages.
    Evaluates test suite quality by introducing deliberate bugs into code and verifying that tests
    catch them. Intelligent file filtering, 18 mutation strategies, sound equivalent-mutant handling, and more.
    """
  end

  defp package do
    [
      name: @app,
      files: ~w(
        lib
        .formatter.exs
        mix.exs
        README.md
        USAGE.md
        LICENSE
        docs/INSTALLATION.md
        docs/MUTATION_OPTIMIZATION.md
        docs/COMPARISON.md
      ),
      licenses: ["MIT"],
      maintainers: ["Aleksei Matiushkin"],
      links: %{
        "GitHub" => @source_url,
        "Documentation" => "https://hexdocs.pm/#{@app}"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "stuff/img/logo-48x48.png",
      assets: %{"stuff/img" => "assets"},
      extras: extras(),
      extra_section: "GUIDES",
      source_url: @source_url,
      source_ref: "v#{@version}",
      formatters: ["html", "epub"],
      groups_for_modules: groups_for_modules(),
      nest_modules_by_prefix: [Muex.Mutator, Muex.Language],
      before_closing_body_tag: &before_closing_body_tag/1,
      authors: ["Aleksei Matiushkin"],
      canonical: "https://hexdocs.pm/#{@app}",
      skip_undefined_reference_warnings_on: []
    ]
  end

  defp extras do
    [
      "README.md",
      "USAGE.md": [title: "Usage Guide"],
      "docs/INSTALLATION.md": [title: "Installation Guide"],
      "docs/MUTATION_OPTIMIZATION.md": [title: "Mutation Optimization"],
      "docs/COMPARISON.md": [title: "Comparison: Muex vs Darwin vs Exavier"]
    ]
  end

  defp groups_for_modules do
    [
      "Core Components": [
        Muex.Compiler,
        Muex.Loader,
        Muex.Runner,
        Muex.Reporter,
        Muex.FileAnalyzer,
        Muex.MutantOptimizer,
        Muex.Coverage,
        Muex.Equivalence,
        Muex.GitDiff,
        Muex.Tce
      ],
      "Language Adapters": [
        Muex.Language,
        Muex.Language.Elixir,
        Muex.Language.Erlang
      ],
      "Mutation Strategies": [
        Muex.Mutator,
        Muex.Mutator.Builders,
        Muex.Mutator.Arithmetic,
        Muex.Mutator.Boolean,
        Muex.Mutator.CaseClause,
        Muex.Mutator.Comparison,
        Muex.Mutator.CondClause,
        Muex.Mutator.Conditional,
        Muex.Mutator.EnumSemantics,
        Muex.Mutator.ExtendedMath,
        Muex.Mutator.FunctionCall,
        Muex.Mutator.Guard,
        Muex.Mutator.InvertNegatives,
        Muex.Mutator.Literal,
        Muex.Mutator.MapSemantics,
        Muex.Mutator.NegateConditionals,
        Muex.Mutator.Pipe,
        Muex.Mutator.ReturnValue,
        Muex.Mutator.StatementDeletion,
        Muex.Mutator.WithClause
      ],
      Reporters: [
        Muex.Reporter.Html,
        Muex.Reporter.Json,
        Muex.Reporter.Patch
      ],
      Utilities: [
        Muex.CLI,
        Muex.DependencyAnalyzer,
        Muex.TestDependency,
        Muex.TestRunner.Port,
        Muex.WorkerPool,
        Mix.Tasks.Muex.Install
      ]
    ]
  end

  defp before_closing_body_tag(:html) do
    """
    <script>
      // Add search keyboard shortcut
      document.addEventListener("keydown", function(e) {
        if (e.key === "/" && !e.ctrlKey && !e.metaKey) {
          e.preventDefault();
          document.querySelector(".search-input")?.focus();
        }
      });
    </script>
    """
  end

  defp before_closing_body_tag(_), do: ""
end
