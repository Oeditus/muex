defmodule Mix.Tasks.Muex do
  @moduledoc """
  Run mutation testing on your project.

  ## Usage

      mix muex [options]

  ## Options

    * `--files` - Glob pattern for files to mutate (default: "lib/**/*.ex")
    * `--language` - Language adapter to use (default: "elixir")
    * `--mutators` - Comma-separated list of mutators (default: all)
    * `--concurrency` - Number of parallel mutations (default: number of schedulers)
    * `--timeout` - Test timeout in milliseconds (default: 5000)
    * `--fail-at` - Minimum mutation score to pass (default: 0)

  ## Examples

      # Run on all lib files
      mix muex

      # Run on specific files
      mix muex --files "lib/my_module.ex"

      # Use specific mutators
      mix muex --mutators arithmetic,comparison

      # Fail if mutation score below 80%
      mix muex --fail-at 80
  """

  use Mix.Task

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
          fail_at: :integer
        ]
      )

    directory = Keyword.get(opts, :files, "lib")
    language_adapter = get_language_adapter(Keyword.get(opts, :language, "elixir"))
    mutators = get_mutators(Keyword.get(opts, :mutators))
    concurrency = Keyword.get(opts, :concurrency, System.schedulers_online())
    timeout_ms = Keyword.get(opts, :timeout, 5000)
    fail_at = Keyword.get(opts, :fail_at, 0)

    Mix.shell().info("Loading files from #{directory}...")

    {:ok, files} = Muex.Loader.load(directory, language_adapter)

    Mix.shell().info("Found #{length(files)} file(s)")
    Mix.shell().info("Generating mutations...")

    all_mutations =
      Enum.flat_map(files, fn file ->
        context = %{file: file.path}
        Muex.Mutator.walk(file.ast, mutators, context)
      end)

    Mix.shell().info("Generated #{length(all_mutations)} mutation(s)")
    Mix.shell().info("Running tests...")

    # For now, we'll run mutations per file
    results =
      Enum.flat_map(files, fn file ->
        file_mutations =
          Enum.filter(all_mutations, fn m ->
            m.location.file == file.path
          end)

        if length(file_mutations) > 0 do
          Muex.Runner.run_all(file_mutations, file, language_adapter,
            concurrency: concurrency,
            timeout_ms: timeout_ms
          )
        else
          []
        end
      end)

    Muex.Reporter.print_summary(results)

    # Check if we meet the minimum score
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

  defp get_language_adapter("elixir"), do: Muex.Language.Elixir
  defp get_language_adapter("erlang"), do: Muex.Language.Erlang
  defp get_language_adapter(other), do: Mix.raise("Unknown language: #{other}")

  defp get_mutators(nil) do
    [Muex.Mutator.Arithmetic, Muex.Mutator.Comparison]
  end

  defp get_mutators(mutators_string) do
    mutators_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&get_mutator/1)
  end

  defp get_mutator("arithmetic"), do: Muex.Mutator.Arithmetic
  defp get_mutator("comparison"), do: Muex.Mutator.Comparison
  defp get_mutator(other), do: Mix.raise("Unknown mutator: #{other}")
end
