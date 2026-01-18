defmodule Mix.Tasks.Muex do
  @moduledoc """
  Run mutation testing on your project.

  ## Usage

      mix muex [options]

  ## Options

    * `--files` - Directory, file, or glob pattern (default: "lib")
    * `--language` - Language adapter to use (default: "elixir")
    * `--mutators` - Comma-separated list of mutators (default: all)
    * `--concurrency` - Number of parallel mutations (default: number of schedulers)
    * `--timeout` - Test timeout in milliseconds (default: 5000)
    * `--fail-at` - Minimum mutation score to pass (default: 0)
    * `--format` - Output format: terminal, json, html (default: terminal)
    * `--min-score` - Minimum complexity score for files to include (default: 20)
    * `--max-mutations` - Maximum number of mutations to test (0 = unlimited, default: 0)
    * `--no-filter` - Disable intelligent file filtering
    * `--verbose` - Show file analysis details

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

      # Show file analysis details
      mix muex --verbose

      # Fail if mutation score below 80%
      mix muex --fail-at 80

      # Generate JSON report
      mix muex --format json

      # Generate HTML report
      mix muex --format html
  """
  use Mix.Task
  alias Muex.Reporter, as: R
  @shortdoc "Run mutation testing"
  @impl Mix.Task
  def run(args) do
    {opts, _args, _invalid} =
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
          verbose: :boolean
        ]
      )

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

    Mix.shell().info("Loading files from #{path_pattern}...")
    {:ok, all_files} = Muex.Loader.load(path_pattern, language_adapter)
    Mix.shell().info("Found #{length(all_files)} file(s)")

    files =
      if no_filter do
        Mix.shell().info("Skipping file filtering (--no-filter enabled)")
        all_files
      else
        Mix.shell().info("Analyzing files for mutation testing suitability...")

        {included, excluded} =
          Muex.FileAnalyzer.filter_files(all_files, min_score: min_score, verbose: verbose)

        if verbose do
          Mix.shell().info("")
        end

        Mix.shell().info("Selected #{length(included)} file(s) for mutation testing")
        Mix.shell().info("Skipped #{length(excluded)} file(s) (low complexity or framework code)")
        included
      end

    Mix.shell().info("Generating mutations...")

    all_mutations =
      files
      |> Enum.flat_map(fn file ->
        context = %{file: file.path}
        Muex.Mutator.walk(file.ast, mutators, context)
      end)
      |> then(fn mutations ->
        if max_mutations > 0 and length(mutations) > max_mutations do
          Mix.shell().info(
            "Limiting to first #{max_mutations} mutations (from #{length(mutations)} total)"
          )

          Enum.take(mutations, max_mutations)
        else
          mutations
        end
      end)

    Mix.shell().info("Testing #{length(all_mutations)} mutation(s)")
    Mix.shell().info("Analyzing test dependencies...")
    dependency_map = Muex.DependencyAnalyzer.analyze("test")
    file_to_module = Map.new(files, fn file -> {file.path, file.module_name} end)
    Mix.shell().info("Running tests...\n")

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
      Muex.Mutator.Literal,
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

  defp output_report(results, "json") do
    R.Json.generate(results)
    Mix.shell().info("JSON report generated: muex-report.json")
  end

  defp output_report(results, "html") do
    R.Html.generate(results)
    Mix.shell().info("HTML report generated: muex-report.html")
  end

  defp output_report(results, "terminal") do
    R.print_summary(results)
  end

  defp output_report(_results, other) do
    Mix.raise("Unknown format: #{other}. Use terminal, json, or html")
  end
end
