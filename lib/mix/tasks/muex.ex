defmodule Mix.Tasks.Muex do
  @moduledoc """
  Run mutation testing on your project.

  ## Usage

      mix muex [options]

  ## Options

    * `--files` - Directory, file, or glob pattern (default: "lib")
    * `--path` - Synonym for --files
    * `--app` - Target a specific app in an umbrella project (sets --files and --test-paths automatically)
    * `--test-paths` - Comma-separated test directories, files, or glob patterns (default: "test")
    * `--language` - Language adapter to use (default: "elixir")
    * `--mutators` - Comma-separated list of mutators (default: all)
    * `--concurrency` - Number of parallel mutations (default: number of schedulers)
    * `--timeout` - Test timeout in milliseconds (default: 10000)
    * `--fail-at` - Minimum mutation score to pass (default: 80)
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
    * `--keep-metadata-mutations` - Keep mutations with no source location (line: 0); dropped by default
    * `--preset` - Framework preset to prune DSL noise: phoenix, ecto, ash, none (default: none)

  ## Examples

      mix muex                          # Run with intelligent filtering
      mix muex --no-filter                # Run on all files
      mix muex --files "lib/muex"          # Specific directory
      mix muex --files "lib/muex/*.ex"     # Glob pattern
      mix muex --mutators arithmetic,comparison
      mix muex --fail-at 80               # Fail below 80%
      mix muex --format json              # JSON output
      mix muex --format html              # HTML report
      mix muex --verbose                  # Detailed progress
      mix muex --optimize --optimize-level aggressive
      mix muex --app my_app               # Umbrella: specific app
      mix muex --test-paths "test/unit,test/integration"
      mix muex --preset phoenix           # Prune Phoenix component/router DSL noise
      mix muex --files "lib/my_module.ex" --test-paths "test/my_module_test.exs"
  """

  use Mix.Task

  @shortdoc "Run mutation testing"
  @impl Mix.Task
  def run(args) do
    case Muex.Config.from_args(args) do
      {:error, reason} ->
        Mix.raise(reason)

      {:ok, config} ->
        case Muex.run(config) do
          {:error, reason} ->
            Mix.raise(reason)

          {:ok, %{score_low: score_low, score_high: score_high}} ->
            # Use the pessimistic (low) bound for threshold comparison.
            # If even the best-case interpretation fails, the score is too low.
            if score_low < config.fail_at do
              score_str =
                if score_low == score_high,
                  do: "#{score_low}%",
                  else: "#{score_low}%..#{score_high}%"

              Mix.raise("Mutation score #{score_str} is below threshold #{config.fail_at}%")
            end
        end
    end
  end
end
