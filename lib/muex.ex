defmodule Muex do
  @moduledoc """
  Muex - Mutation testing library for Elixir, Erlang, and other languages.

  Muex provides a language-agnostic mutation testing framework with dependency
  injection for language adapters, making it easy to extend support to new languages.

  ## Architecture

  - `Muex.Language` - Behaviour for language adapters (parse, unparse, compile)
  - `Muex.Mutator` - Behaviour for mutation strategies
  - `Muex.Loader` - Discovers and loads source files
  - `Muex.Compiler` - Compiles mutated code and manages hot-swapping
  - `Muex.Runner` - Executes tests against mutants
  - `Muex.Reporter` - Reports mutation testing results

  ## Usage

  Run mutation testing via Mix task:

      mix muex

  With options:

      mix muex --files "lib/**/*.ex" --mutators arithmetic,comparison --fail-at 80

  ## Creating a Language Adapter

  To add support for a new language, implement the `Muex.Language` behaviour:

      defmodule Muex.Language.MyLanguage do
        @behaviour Muex.Language

        @impl true
        def parse(source), do: {:ok, parse_to_ast(source)}

        @impl true
        def unparse(ast), do: {:ok, ast_to_string(ast)}

        @impl true
        def compile(source, module_name), do: {:ok, compiled_module}

        @impl true
        def file_extensions, do: [".mylang"]

        @impl true
        def test_file_pattern, do: ~r/_test\.mylang$/
      end

  ## Creating a Mutator

  To add a new mutation strategy, implement the `Muex.Mutator` behaviour:

      defmodule Muex.Mutator.MyMutator do
        @behaviour Muex.Mutator

        @impl true
        def mutate(ast, context) do
          # Return list of mutations
          []
        end

        @impl true
        def name, do: "MyMutator"

        @impl true
        def description, do: "Custom mutation strategy"
      end
  """

  alias Muex.Reporter.Html, as: HtmlReporter
  alias Muex.Reporter.Json, as: JsonReporter

  @doc """
  Executes the full mutation testing pipeline from a `%Muex.Config{}`.

  Returns `{:ok, %{results: results, score: mutation_score}}` on success
  or `{:error, reason}` on failure. Never calls `Mix.raise` or `System.halt`;
  the caller decides how to handle the outcome.
  """
  @spec run(Muex.Config.t()) :: {:ok, map()} | {:error, String.t()}
  def run(%Muex.Config{} = config) do
    log("Loading files from #{Enum.join(config.files, ", ")}...", config.verbose)

    case Muex.Loader.load_all(config.files, config.language) do
      {:ok, []} ->
        {:ok, %{results: [], score_low: 0.0, score_high: 0.0}}

      {:ok, [_ | _] = all_files} ->
        # Normalize file paths to be relative to the project root so that
        # downstream code (sandbox, PortRunner) can join them correctly.
        all_files = relativize_file_entries(all_files, config.project_root)
        log("Found #{length(all_files)} file(s)", config.verbose)
        do_run(config, all_files)
    end
  end

  defp do_run(config, all_files) do
    files = maybe_filter(all_files, config)

    log("Generating mutations...", config.verbose)

    all_mutations =
      files
      |> Enum.flat_map(fn file ->
        context = %{file: file.path, skip_calls: config.skip_calls}
        Muex.Mutator.walk(file.ast, config.mutators, context)
      end)
      |> maybe_drop_unlocatable(config)
      |> maybe_optimize(config)
      |> maybe_cap(config)

    if all_mutations == [] do
      {:ok, %{results: [], score_low: 0.0, score_high: 0.0}}
    else
      run_mutations(config, files, all_mutations)
    end
  end

  defp maybe_filter(files, %Muex.Config{filter: false} = config) do
    log("Skipping file filtering", config.verbose)
    files
  end

  defp maybe_filter(files, %Muex.Config{filter: true} = config) do
    log("Analyzing files for mutation testing suitability...", config.verbose)

    {included, excluded} =
      Muex.FileAnalyzer.filter_files(files, min_score: config.min_score, verbose: config.verbose)

    log(
      "Selected #{length(included)} file(s), skipped #{length(excluded)} file(s)",
      config.verbose
    )

    included
  end

  # Drop mutations with no usable source location (line: 0). These are
  # typically compile-time metadata or macro-generated nodes that produce
  # invalid mutants and clutter reports. Opt out with --keep-metadata-mutations.
  defp maybe_drop_unlocatable(mutations, %Muex.Config{keep_metadata: true}), do: mutations

  defp maybe_drop_unlocatable(mutations, %Muex.Config{verbose: verbose}) do
    {located, unlocated} = Enum.split_with(mutations, &locatable?/1)

    if verbose and unlocated != [] do
      log("Dropping #{length(unlocated)} mutation(s) with no source location (line: 0)", true)
    end

    located
  end

  defp locatable?(mutation) do
    case get_in(mutation, [:location, :line]) do
      line when is_integer(line) and line > 0 -> true
      _ -> false
    end
  end

  defp maybe_optimize(mutations, %Muex.Config{optimize: false}), do: mutations

  defp maybe_optimize(mutations, %Muex.Config{optimize: true, verbose: verbose} = config) do
    log("Applying mutation optimization...", verbose)
    opts = Muex.Config.optimizer_opts(config)
    optimized = Muex.MutantOptimizer.optimize(mutations, opts)

    if verbose do
      report = Muex.MutantOptimizer.optimization_report(mutations, optimized)
      log("Original mutations: #{report.original_count}", true)
      log("Optimized mutations: #{report.optimized_count}", true)
      log("Reduction: #{report.reduction} (-#{report.reduction_percentage}%)", true)
      log("Average impact score: #{report.average_impact_score}", true)
    end

    optimized
  end

  defp maybe_cap(mutations, %Muex.Config{max_mutations: max})
       when max > 0 and length(mutations) > max do
    Enum.take(mutations, max)
  end

  defp maybe_cap(mutations, _config), do: mutations

  defp run_mutations(config, files, all_mutations) do
    log("Testing #{length(all_mutations)} mutation(s)", config.verbose)
    log("Analyzing test dependencies...", config.verbose)

    # Make test paths absolute so DependencyAnalyzer and the worker pool
    # can find files on disk regardless of CWD. Config stores them as-is
    # (relative or absolute) — we absolutize here, once.
    abs_test_paths = absolutize_paths(config.test_paths, config.project_root)

    dependency_map = Muex.DependencyAnalyzer.analyze(abs_test_paths)
    file_entries = Map.new(files, fn file -> {file.path, file} end)
    file_to_module = Map.new(files, fn file -> {file.path, file.module_name} end)

    log(
      "Running tests...
",
      config.verbose
    )

    results =
      Muex.Runner.run_all(
        all_mutations,
        file_entries,
        config.language,
        dependency_map,
        file_to_module,
        max_workers: config.concurrency,
        timeout_ms: config.timeout_ms,
        verbose: config.verbose,
        test_paths: abs_test_paths,
        project_root: config.project_root
      )

    case output_report(results, config.format, config.verbose) do
      {:error, _} = err -> err
      _ -> build_result(results)
    end
  end

  defp build_result(results) do
    killed = Enum.count(results, &(&1.result == :killed))
    survived = Enum.count(results, &(&1.result == :survived))
    timeout = Enum.count(results, &(&1.result == :timeout))

    # Invalids are excluded: they tell us nothing about test quality.
    # Timeouts are ambiguous -- they could be killed or survived.
    denom = killed + survived + timeout

    {score_low, score_high} =
      if denom > 0 do
        # Low bound (pessimistic): assume all timeouts survived
        low = Float.round(killed / denom * 100, 2)
        # High bound (optimistic): assume all timeouts were killed
        high = Float.round((killed + timeout) / denom * 100, 2)
        {low, high}
      else
        {0.0, 0.0}
      end

    {:ok, %{results: results, score_low: score_low, score_high: score_high}}
  end

  defp output_report(results, "json", _verbose) do
    log(JsonReporter.to_json(results))
  end

  defp output_report(results, "html", verbose) do
    HtmlReporter.generate(results)
    log("HTML report generated: muex-report.html", verbose)
  end

  defp output_report(results, "terminal", _verbose) do
    Muex.Reporter.print_summary(results)
  end

  defp output_report(_results, other, _verbose) do
    {:error, "Unknown format: #{other}. Use terminal, json, or html"}
  end

  # Convert relative paths to absolute, anchored at `root`.
  defp absolutize_paths(paths, root) do
    Enum.map(paths, fn path ->
      case Path.type(path) do
        :absolute -> path
        _ -> Path.join(root, path)
      end
    end)
  end

  # Make all file paths relative to the project root. This is essential
  # when --path points to an external project: the Loader returns absolute
  # paths, but the sandbox expects paths relative to its project root.
  defp relativize_file_entries(files, project_root) do
    Enum.map(files, fn file ->
      relative_path =
        file.path
        |> Path.expand()
        |> Path.relative_to(project_root)

      %{file | path: relative_path}
    end)
  end

  defp log(msg, verbose \\ true) do
    if verbose do
      if Code.ensure_loaded?(Mix) and function_exported?(Mix, :shell, 0) do
        Mix.shell().info(msg)
      else
        IO.puts(msg)
      end
    end
  end
end
