defmodule Mix.Tasks.Muex do
  @moduledoc """
  Run mutation testing on your project.

  ## Usage

      mix muex [options]

  ## Options

    * `--files` - Directory, file, or glob pattern (default: "lib")
    * `--path` - Synonym for --files
    * `--language` - Language adapter to use (default: "elixir")
    * `--mutators` - Comma-separated list of mutators (default: all)
    * `--concurrency` - Number of parallel mutations (default: number of schedulers)
    * `--timeout` - Test timeout in milliseconds (default: 5000)
    * `--fail-at` - Minimum mutation score to pass (default: 100)
    * `--format` - Output format: terminal, json, html (default: terminal)
    * `--min-score` - Minimum complexity score for files to include (default: 20)
    * `--max-mutations` - Maximum number of mutations to test (0 = unlimited, default: 0)
    * `--no-filter` - Disable intelligent file filtering
    * `--verbose` - Show detailed progress information (file analysis, optimization, etc.)
    * `--optimize` - Enable mutation optimization heuristics (default: enabled)
    * `--no-optimize` - Disable mutation optimization heuristics
    * `--optimize-level` - Optimization preset: conservative, balanced, aggressive (default: balanced)
    * `--min-complexity` - Minimum complexity for mutations (default: 2, with --optimize)
    * `--max-per-function` - Max mutations per function (default: 20, with --optimize)

  ## Examples

      # Run on all lib files (with intelligent filtering)
      mix muex

      # Run on all files without filtering
      mix muex --no-filter

      # Run on specific directory
      mix muex --files "lib/muex"

      # Run on specific file
      mix muex --files "lib/my_module.ex"

      # Run with glob patterns
      mix muex --files "lib/muex/*.ex"
      mix muex --files "lib/**/compiler*.ex"

      # Use specific mutators
      mix muex --mutators arithmetic,comparison,boolean,literal,function_call,conditional

      # Set minimum complexity score
      mix muex --min-score 30

      # Limit total mutations to test
      mix muex --max-mutations 500

      # Show detailed progress information
      mix muex --verbose

      # Fail if mutation score below 80%
      mix muex --fail-at 80

      # Output JSON to terminal
      mix muex --format json

      # Output JSON with progress details
      mix muex --format json --verbose

      # Generate HTML report (writes to muex-report.html)
      mix muex --format html

      # Enable mutation optimization (balanced preset)
      mix muex --optimize

      # Use aggressive optimization
      mix muex --optimize --optimize-level aggressive

      # Custom optimization settings
      mix muex --optimize --min-complexity 3 --max-per-function 15
  """

  use Mix.Task
  alias Muex.Reporter, as: R

  @shortdoc "Run mutation testing"
  @impl Mix.Task
  # credo:disable-for-lines:167
  def run(args) do
    {opts, _args, _invalid} =
      OptionParser.parse(args,
        strict: [
          files: :string,
          path: :string,
          language: :string,
          mutators: :string,
          concurrency: :integer,
          timeout: :integer,
          fail_at: :integer,
          format: :string,
          min_score: :integer,
          max_mutations: :integer,
          no_filter: :boolean,
          verbose: :boolean,
          optimize: :boolean,
          no_optimize: :boolean,
          optimize_level: :string,
          min_complexity: :integer,
          max_per_function: :integer
        ]
      )

    path_pattern = Keyword.get(opts, :path) || Keyword.get(opts, :files, "lib")
    language_adapter = get_language_adapter(Keyword.get(opts, :language, "elixir"))
    mutators = get_mutators(Keyword.get(opts, :mutators))
    concurrency = Keyword.get(opts, :concurrency, System.schedulers_online())
    timeout_ms = Keyword.get(opts, :timeout, 5000)
    fail_at = Keyword.get(opts, :fail_at, 100)
    min_score = Keyword.get(opts, :min_score, 20)
    max_mutations = Keyword.get(opts, :max_mutations, 0)
    no_filter = Keyword.get(opts, :no_filter, false)
    verbose = Keyword.get(opts, :verbose, false)

    optimize =
      cond do
        Keyword.get(opts, :no_optimize, false) -> false
        Keyword.has_key?(opts, :optimize) -> Keyword.get(opts, :optimize)
        true -> true
      end

    optimize_level = Keyword.get(opts, :optimize_level, "balanced")
    min_complexity = Keyword.get(opts, :min_complexity)
    max_per_function = Keyword.get(opts, :max_per_function)

    format = Keyword.get(opts, :format, "terminal")

    if verbose do
      Mix.shell().info("Loading files from #{path_pattern}...")
    end

    {:ok, all_files} = Muex.Loader.load(path_pattern, language_adapter)

    if verbose do
      Mix.shell().info("Found #{length(all_files)} file(s)")
    end

    files =
      if no_filter do
        if verbose do
          Mix.shell().info("Skipping file filtering (--no-filter enabled)")
        end

        all_files
      else
        if verbose do
          Mix.shell().info("Analyzing files for mutation testing suitability...")
        end

        {included, excluded} =
          Muex.FileAnalyzer.filter_files(all_files, min_score: min_score, verbose: verbose)

        if verbose do
          Mix.shell().info("")
          Mix.shell().info("Selected #{length(included)} file(s) for mutation testing")

          Mix.shell().info(
            "Skipped #{length(excluded)} file(s) (low complexity or framework code)"
          )
        end

        included
      end

    if verbose do
      Mix.shell().info("Generating mutations...")
    end

    all_mutations =
      files
      |> Enum.flat_map(fn file ->
        context = %{file: file.path}
        Muex.Mutator.walk(file.ast, mutators, context)
      end)
      |> then(fn mutations ->
        optimized =
          if optimize do
            if verbose do
              Mix.shell().info("Applying mutation optimization...")
            end

            optimizer_opts = get_optimizer_opts(optimize_level, min_complexity, max_per_function)
            Muex.MutantOptimizer.optimize(mutations, optimizer_opts)
          else
            mutations
          end

        if optimize and verbose do
          report = Muex.MutantOptimizer.optimization_report(mutations, optimized)
          Mix.shell().info("Original mutations: #{report.original_count}")
          Mix.shell().info("Optimized mutations: #{report.optimized_count}")
          Mix.shell().info("Reduction: #{report.reduction} (-#{report.reduction_percentage}%)")
          Mix.shell().info("Average impact score: #{report.average_impact_score}")
        end

        if max_mutations > 0 and length(optimized) > max_mutations do
          if verbose do
            Mix.shell().info(
              "Limiting to first #{max_mutations} mutations (from #{length(optimized)} total)"
            )
          end

          Enum.take(optimized, max_mutations)
        else
          optimized
        end
      end)

    if verbose do
      Mix.shell().info("Testing #{length(all_mutations)} mutation(s)")
      Mix.shell().info("Analyzing test dependencies...")
    end

    dependency_map = Muex.DependencyAnalyzer.analyze("test")
    file_to_module = Map.new(files, fn file -> {file.path, file.module_name} end)

    if verbose do
      Mix.shell().info("Running tests...\n")
    end

    results =
      Enum.flat_map(files, fn file ->
        file_mutations = Enum.filter(all_mutations, fn m -> m.location.file == file.path end)

        if match?([_ | _], file_mutations) do
          Muex.Runner.run_all(
            file_mutations,
            file,
            language_adapter,
            dependency_map,
            file_to_module,
            max_workers: concurrency,
            timeout_ms: timeout_ms,
            verbose: verbose
          )
        else
          []
        end
      end)

    output_report(results, format, verbose)
    total = length(results)
    killed = Enum.count(results, &(&1.result == :killed))

    mutation_score =
      if total > 0 do
        Float.round(killed / total * 100, 2)
      else
        0.0
      end

    if mutation_score < fail_at do
      Mix.raise("Mutation score #{mutation_score}% is below threshold #{fail_at}%")
    end
  end

  defp get_language_adapter("elixir") do
    Muex.Language.Elixir
  end

  defp get_language_adapter("erlang") do
    Muex.Language.Erlang
  end

  defp get_language_adapter(other) do
    Mix.raise("Unknown language: #{other}. Use elixir or erlang")
  end

  defp get_mutators(nil) do
    [
      Muex.Mutator.Arithmetic,
      Muex.Mutator.Comparison,
      Muex.Mutator.Boolean,
      Muex.Mutator.FunctionCall,
      Muex.Mutator.Conditional
    ]
  end

  defp get_mutators(mutators_string) do
    mutators_string |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.map(&get_mutator/1)
  end

  defp get_mutator("arithmetic") do
    Muex.Mutator.Arithmetic
  end

  defp get_mutator("comparison") do
    Muex.Mutator.Comparison
  end

  defp get_mutator("boolean") do
    Muex.Mutator.Boolean
  end

  defp get_mutator("literal") do
    Muex.Mutator.Literal
  end

  defp get_mutator("function_call") do
    Muex.Mutator.FunctionCall
  end

  defp get_mutator("conditional") do
    Muex.Mutator.Conditional
  end

  defp get_mutator(other) do
    Mix.raise("Unknown mutator: #{other}")
  end

  defp output_report(results, "json", _verbose) do
    json = R.Json.to_json(results)
    Mix.shell().info(json)
  end

  defp output_report(results, "html", verbose) do
    R.Html.generate(results)

    if verbose do
      Mix.shell().info("HTML report generated: muex-report.html")
    end
  end

  defp output_report(results, "terminal", _verbose) do
    R.print_summary(results)
  end

  defp output_report(_results, other, _verbose) do
    Mix.raise("Unknown format: #{other}. Use terminal, json, or html")
  end

  defp get_optimizer_opts(level, min_complexity_override, max_per_function_override) do
    base_opts =
      case level do
        "conservative" ->
          [
            enabled: true,
            min_complexity: 1,
            max_mutations_per_function: 50,
            cluster_similarity_threshold: 0.8,
            keep_boundary_mutations: true
          ]

        "balanced" ->
          [
            enabled: true,
            min_complexity: 2,
            max_mutations_per_function: 20,
            cluster_similarity_threshold: 0.8,
            keep_boundary_mutations: true
          ]

        "aggressive" ->
          [
            enabled: true,
            min_complexity: 3,
            max_mutations_per_function: 10,
            cluster_similarity_threshold: 0.8,
            keep_boundary_mutations: true
          ]

        other ->
          Mix.raise(
            "Unknown optimization level: #{other}. Use conservative, balanced, or aggressive"
          )
      end

    # Override with explicit flags if provided
    base_opts =
      if min_complexity_override do
        Keyword.put(base_opts, :min_complexity, min_complexity_override)
      else
        base_opts
      end

    if max_per_function_override do
      Keyword.put(base_opts, :max_mutations_per_function, max_per_function_override)
    else
      base_opts
    end
  end
end
