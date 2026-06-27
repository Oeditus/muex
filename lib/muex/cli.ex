defmodule Muex.CLI do
  @moduledoc """
  Command-line interface for Muex mutation testing.

  This module provides the escript entry point. It parses arguments via
  `Muex.Config.from_args/1` and delegates execution to `Muex.run/1`.
  """

  @spec main([String.t()]) :: no_return()
  def main(args) do
    {:ok, _} = Application.ensure_all_started(:muex)
    {:ok, _} = Application.ensure_all_started(:jason)

    case args do
      ["--help" | _] ->
        print_help()
        System.halt(0)

      ["-h" | _] ->
        print_help()
        System.halt(0)

      ["--version" | _] ->
        print_version()
        System.halt(0)

      ["-v" | _] ->
        print_version()
        System.halt(0)

      _ ->
        run_mutation_testing(args)
    end
  end

  @spec run_mutation_testing([String.t()]) :: no_return()
  defp run_mutation_testing(args) do
    case Muex.Config.from_args(args) do
      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)

      {:ok, config} ->
        unless File.exists?("mix.exs") do
          IO.puts(:stderr, "Error: No mix.exs found in current directory")
          IO.puts(:stderr, "Please run muex from the root of an Elixir project")
          System.halt(1)
        end

        Mix.start()
        Mix.Task.run("loadpaths")
        Mix.Task.run("compile", ["--no-deps-check"])

        case Muex.run(config) do
          {:ok, %{results: []}} ->
            # No mutations were generated (e.g. --since with no mutable changes).
            # There is nothing to score, so the run passes the gate.
            IO.puts("No mutations to test; nothing to score.")
            System.halt(0)

          {:ok, %{score_low: score_low, score_high: score_high}} ->
            if score_low < config.fail_at do
              score_str =
                if score_low == score_high,
                  do: "#{score_low}%",
                  else: "#{score_low}%..#{score_high}%"

              IO.puts(
                :stderr,
                "Mutation score #{score_str} is below threshold #{config.fail_at}%"
              )

              System.halt(1)
            end

            System.halt(0)

          {:error, reason} ->
            IO.puts(:stderr, "Error: #{reason}")
            System.halt(1)
        end
    end
  rescue
    e ->
      IO.puts(:stderr, "Error: #{Exception.message(e)}")
      IO.puts(:stderr, Exception.format_stacktrace(__STACKTRACE__))
      System.halt(1)
  end

  defp print_help do
    IO.puts("""
    Muex - Mutation Testing for Elixir and Erlang
    USAGE:
        muex [OPTIONS]
    OPTIONS:
        --files <pattern>           Directory, file, or glob pattern (default: "lib")
        --path <pattern>            Synonym for --files
        --app <name>               Target app in umbrella project
        --test-paths <paths>       Comma-separated test dirs/files/globs (default: "test")
        --language <lang>           Language adapter: elixir, erlang (default: elixir)
        --mutators <list>           Comma-separated mutators (default: all)
        --mutator-paths <dirs>      Comma-separated dirs with custom mutators
        --concurrency <n>           Parallel mutations (default: CPU cores)
        --timeout <ms>              Test timeout in milliseconds (default: 10000)
        --fail-at <score>           Minimum mutation score to pass (default: 80)
        --format <type>             Output format: terminal, json, html (default: terminal)
        --min-score <score>         Minimum complexity score for files (default: 20)
        --max-mutations <n>         Maximum mutations to test (default: unlimited)
        --no-filter                 Disable intelligent file filtering
        --verbose                   Show detailed progress information
        --optimize                  Enable mutation optimization (default: enabled)
        --no-optimize               Disable mutation optimization
        --optimize-level <level>    Optimization: conservative, balanced, aggressive
        --min-complexity <n>        Minimum complexity for mutations (default: 2)
        --max-per-function <n>      Max mutations per function (default: 20)
        --tce / --no-tce            Trivial Compiler Equivalence (default: enabled)
        --since <ref>               Only mutate lines changed since a git ref
        --coverage-guided           Run only tests covering each mutated line
        -h, --help                  Show this help message
        -v, --version               Show version information
    MUTATORS:
        arithmetic           Mutate arithmetic operators (+, -, *, /)
        comparison           Mutate comparison operators (==, !=, <, >, <=, >=)
        boolean              Mutate boolean operators (and, or, not, true, false)
        literal              Mutate literal values (numbers, strings, lists, atoms)
        function_call        Mutate function calls (remove, swap arguments)
        conditional          Mutate conditionals (if, unless)
        return_value         Mutate function/block return values
        statement_deletion   Delete individual statements from blocks
        pipe                 Drop a stage from a pipe chain (x |> f becomes x)
        guard                Remove a when guard (replace with true)
        case_clause          Delete a clause from a case expression
        cond_clause          Delete a clause from a cond expression
        with_clause          Delete a clause from a with expression
        map_semantics        Mutate map operations (Elixir-specific)
        enum_semantics       Mutate Enum operations (Elixir-specific)
        extended_math        Mutate rem, div, and bitwise operators
        invert_negatives     Drop unary negation (-x becomes x)
        negate_conditionals  Swap relational operators for their complements
    EXAMPLES:
        # Run on all lib files
        muex
        # Run on specific directory
        muex --files "lib/muex"
        # Umbrella: target specific app
        muex --app my_app
        # Custom test paths
        muex --test-paths "test/unit,test/integration"
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
