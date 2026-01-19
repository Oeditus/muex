defmodule Muex.CLI do
  @moduledoc """
  Command-line interface for Muex mutation testing.

  This module provides the escript entry point that delegates to the Mix task.
  """

  alias Muex.Reporter, as: R

  @doc """
  Main entry point for the escript.

  Parses command-line arguments and runs mutation testing.
  """
  @spec main([String.t()]) :: no_return()
  def main(args) do
    # Start required applications
    {:ok, _} = Application.ensure_all_started(:muex)
    {:ok, _} = Application.ensure_all_started(:jason)

    # Parse and run
    case parse_args(args) do
      {:help, _} ->
        print_help()
        System.halt(0)

      {:version, _} ->
        print_version()
        System.halt(0)

      {:run, opts} ->
        run_mutation_testing(opts)
    end
  end

  defp parse_args(["--help" | _]), do: {:help, []}
  defp parse_args(["-h" | _]), do: {:help, []}
  defp parse_args(["--version" | _]), do: {:version, []}
  defp parse_args(["-v" | _]), do: {:version, []}
  defp parse_args(args), do: {:run, args}

  # credo:disable-for-lines:165
  @spec run_mutation_testing([String.t()]) :: no_return()
  defp run_mutation_testing(args) do
    {opts, _args, invalid} =
      OptionParser.parse(args,
        strict: [
          files: :string,
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
          optimize_level: :string,
          min_complexity: :integer,
          max_per_function: :integer
        ]
      )

    if match?([_ | _], invalid) do
      IO.puts(:stderr, "Invalid options: #{inspect(invalid)}")
      IO.puts(:stderr, "Use --help for usage information")
      System.halt(1)
    end

    # Ensure we're in a project directory
    unless File.exists?("mix.exs") do
      IO.puts(:stderr, "Error: No mix.exs found in current directory")
      IO.puts(:stderr, "Please run muex from the root of an Elixir project")
      System.halt(1)
    end

    # Load the project's Mix configuration
    Mix.start()
    Mix.Task.run("loadpaths")
    Mix.Task.run("compile", ["--no-deps-check"])

    # Run the mutation testing
    path_pattern = Keyword.get(opts, :files, "lib")
    language_adapter = get_language_adapter(Keyword.get(opts, :language, "elixir"))
    mutators = get_mutators(Keyword.get(opts, :mutators))
    concurrency = Keyword.get(opts, :concurrency, System.schedulers_online())
    timeout_ms = Keyword.get(opts, :timeout, 5000)
    fail_at = Keyword.get(opts, :fail_at, 0)
    min_score = Keyword.get(opts, :min_score, 20)
    max_mutations = Keyword.get(opts, :max_mutations, 0)
    no_filter = Keyword.get(opts, :no_filter, false)
    verbose = Keyword.get(opts, :verbose, false)
    optimize = Keyword.get(opts, :optimize, false)
    optimize_level = Keyword.get(opts, :optimize_level, "balanced")
    min_complexity = Keyword.get(opts, :min_complexity)
    max_per_function = Keyword.get(opts, :max_per_function)

    IO.puts("Loading files from #{path_pattern}...")
    {:ok, all_files} = Muex.Loader.load(path_pattern, language_adapter)
    IO.puts("Found #{length(all_files)} file(s)")

    files =
      if no_filter do
        IO.puts("Skipping file filtering (--no-filter enabled)")
        all_files
      else
        IO.puts("Analyzing files for mutation testing suitability...")

        {included, excluded} =
          Muex.FileAnalyzer.filter_files(all_files, min_score: min_score, verbose: verbose)

        if verbose do
          IO.puts("")
        end

        IO.puts("Selected #{length(included)} file(s) for mutation testing")
        IO.puts("Skipped #{length(excluded)} file(s) (low complexity or framework code)")
        included
      end

    IO.puts("Generating mutations...")

    all_mutations =
      files
      |> Enum.flat_map(fn file ->
        context = %{file: file.path}
        Muex.Mutator.walk(file.ast, mutators, context)
      end)
      |> then(fn mutations ->
        optimized =
          if optimize do
            IO.puts("Applying mutation optimization...")
            optimizer_opts = get_optimizer_opts(optimize_level, min_complexity, max_per_function)
            Muex.MutantOptimizer.optimize(mutations, optimizer_opts)
          else
            mutations
          end

        if optimize do
          report = Muex.MutantOptimizer.optimization_report(mutations, optimized)
          IO.puts("Original mutations: #{report.original_count}")
          IO.puts("Optimized mutations: #{report.optimized_count}")
          IO.puts("Reduction: #{report.reduction} (-#{report.reduction_percentage}%)")
          IO.puts("Average impact score: #{report.average_impact_score}")
        end

        if max_mutations > 0 and length(optimized) > max_mutations do
          IO.puts(
            "Limiting to first #{max_mutations} mutations (from #{length(optimized)} total)"
          )

          Enum.take(optimized, max_mutations)
        else
          optimized
        end
      end)

    IO.puts("Testing #{length(all_mutations)} mutation(s)")
    IO.puts("Analyzing test dependencies...")
    dependency_map = Muex.DependencyAnalyzer.analyze("test")
    file_to_module = Map.new(files, fn file -> {file.path, file.module_name} end)
    IO.puts("Running tests...\n")

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
            timeout_ms: timeout_ms
          )
        else
          []
        end
      end)

    format = Keyword.get(opts, :format, "terminal")
    output_report(results, format)
    total = length(results)
    killed = Enum.count(results, &(&1.result == :killed))

    mutation_score =
      if total > 0 do
        Float.round(killed / total * 100, 2)
      else
        0.0
      end

    if mutation_score < fail_at do
      IO.puts(:stderr, "Mutation score #{mutation_score}% is below threshold #{fail_at}%")
      System.halt(1)
    end

    System.halt(0)
  rescue
    e ->
      IO.puts(:stderr, "Error: #{Exception.message(e)}")
      IO.puts(:stderr, Exception.format_stacktrace(__STACKTRACE__))
      System.halt(1)
  end

  defp get_language_adapter("elixir"), do: Muex.Language.Elixir
  defp get_language_adapter("erlang"), do: Muex.Language.Erlang

  defp get_language_adapter(other) do
    IO.puts(:stderr, "Unknown language: #{other}. Use elixir or erlang")
    System.halt(1)
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

  defp get_mutator("arithmetic"), do: Muex.Mutator.Arithmetic
  defp get_mutator("comparison"), do: Muex.Mutator.Comparison
  defp get_mutator("boolean"), do: Muex.Mutator.Boolean
  defp get_mutator("literal"), do: Muex.Mutator.Literal
  defp get_mutator("function_call"), do: Muex.Mutator.FunctionCall
  defp get_mutator("conditional"), do: Muex.Mutator.Conditional

  defp get_mutator(other) do
    IO.puts(:stderr, "Unknown mutator: #{other}")
    System.halt(1)
  end

  defp output_report(results, "json") do
    R.Json.generate(results)
    IO.puts("JSON report generated: muex-report.json")
  end

  defp output_report(results, "html") do
    R.Html.generate(results)
    IO.puts("HTML report generated: muex-report.html")
  end

  defp output_report(results, "terminal") do
    R.print_summary(results)
  end

  defp output_report(_results, other) do
    IO.puts(:stderr, "Unknown format: #{other}. Use terminal, json, or html")
    System.halt(1)
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
          IO.puts(
            :stderr,
            "Unknown optimization level: #{other}. Use conservative, balanced, or aggressive"
          )

          System.halt(1)
      end

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

  defp print_help do
    IO.puts("""
    Muex - Mutation Testing for Elixir and Erlang

    USAGE:
        muex [OPTIONS]

    OPTIONS:
        --files <pattern>           Directory, file, or glob pattern (default: "lib")
        --language <lang>           Language adapter: elixir, erlang (default: elixir)
        --mutators <list>           Comma-separated mutators (default: all)
        --concurrency <n>           Parallel mutations (default: CPU cores)
        --timeout <ms>              Test timeout in milliseconds (default: 5000)
        --fail-at <score>           Minimum mutation score to pass (default: 0)
        --format <type>             Output format: terminal, json, html (default: terminal)
        --min-score <score>         Minimum complexity score for files (default: 20)
        --max-mutations <n>         Maximum mutations to test (default: unlimited)
        --no-filter                 Disable intelligent file filtering
        --verbose                   Show file analysis details
        --optimize                  Enable mutation optimization
        --optimize-level <level>    Optimization: conservative, balanced, aggressive
        --min-complexity <n>        Minimum complexity for mutations (default: 2)
        --max-per-function <n>      Max mutations per function (default: 20)
        -h, --help                  Show this help message
        -v, --version               Show version information

    MUTATORS:
        arithmetic      Mutate arithmetic operators (+, -, *, /)
        comparison      Mutate comparison operators (==, !=, <, >, <=, >=)
        boolean         Mutate boolean operators (and, or, not, true, false)
        literal         Mutate literal values (numbers, strings, lists, atoms)
        function_call   Mutate function calls (remove, swap arguments)
        conditional     Mutate conditionals (if, unless)

    EXAMPLES:
        # Run on all lib files
        muex

        # Run on specific directory
        muex --files "lib/muex"

        # Use specific mutators with optimization
        muex --mutators arithmetic,comparison --optimize

        # Fail if mutation score below 80%
        muex --fail-at 80

        # Generate HTML report
        muex --format html

    For more information, visit: https://github.com/Oeditus/muex
    """)
  end

  defp print_version do
    version = Application.spec(:muex, :vsn) |> to_string()
    IO.puts("Muex version #{version}")
  end
end
