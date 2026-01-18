defmodule Muex.FileAnalyzer do
  @moduledoc """
  Analyzes source files to determine which ones should be included in mutation testing.

  Filters out files that are unlikely to benefit from mutation testing:
  - Framework/library internals (behaviours, protocols, supervisors)
  - Generated code and configuration
  - Pure data structures without logic
  - Files without test coverage
  """

  @doc """
  Analyzes a file entry and returns a priority score.

  Returns `{:ok, score}` where score is:
  - 0: should skip (no business logic to test)
  - 1-10: low priority (mostly boilerplate)
  - 11-50: medium priority (some testable logic)
  - 51-100: high priority (significant business logic)

  Returns `{:skip, reason}` if the file should be excluded.
  """
  @spec analyze_file(map()) :: {:ok, non_neg_integer()} | {:skip, String.t()}
  def analyze_file(%{path: path, ast: ast, module_name: module_name}) do
    cond do
      # Skip Mix tasks (CLI layer, not business logic)
      mix_task?(path, module_name) ->
        {:skip, "Mix task"}

      # Skip application/supervisor modules
      application?(ast) or supervisor?(ast) ->
        {:skip, "Application/Supervisor"}

      # Skip behaviour definitions
      behaviour_definition?(ast) ->
        {:skip, "Behaviour definition"}

      # Skip protocol definitions
      protocol?(ast) ->
        {:skip, "Protocol definition"}

      # Skip reporter/formatter modules (output formatting)
      reporter?(path) ->
        {:skip, "Reporter/Formatter"}

      # Skip if in deps directory
      String.contains?(path, "/deps/") ->
        {:skip, "Dependency code"}

      # Calculate score for other files
      true ->
        score = calculate_score(ast, path)
        {:ok, score}
    end
  end

  @doc """
  Filters a list of file entries based on analysis results.

  Options:
  - `:min_score` - Minimum score to include (default: 20)
  - `:verbose` - Show analysis details (default: false)
  """
  @spec filter_files([map()], keyword()) :: {[map()], [map()]}
  def filter_files(files, opts \\ []) do
    min_score = Keyword.get(opts, :min_score, 20)
    verbose = Keyword.get(opts, :verbose, false)

    {included, excluded} =
      Enum.split_with(files, fn file ->
        case analyze_file(file) do
          {:ok, score} when score >= min_score ->
            if verbose do
              Mix.shell().info("  ✓ #{Path.relative_to_cwd(file.path)} (score: #{score})")
            end

            true

          {:ok, score} ->
            if verbose do
              Mix.shell().info(
                "  - #{Path.relative_to_cwd(file.path)} (score: #{score}, below threshold)"
              )
            end

            false

          {:skip, reason} ->
            if verbose do
              Mix.shell().info("  ✗ #{Path.relative_to_cwd(file.path)} (#{reason})")
            end

            false
        end
      end)

    {included, excluded}
  end

  # Check if module is a Mix task
  defp mix_task?(_path, nil), do: false

  defp mix_task?(path, module_name) do
    String.contains?(path, "/mix/tasks/") or
      module_name |> Module.split() |> List.first() == "Mix"
  end

  # Check if module defines an application
  defp application?(ast) do
    has_use?(ast, :Application) or has_callback?(ast, :start)
  end

  # Check if module is a supervisor
  defp supervisor?(ast) do
    has_use?(ast, :Supervisor) or has_callback?(ast, :init)
  end

  # Check if module is a behaviour definition
  defp behaviour_definition?(ast) do
    has_behaviour_directive?(ast) or has_many_callbacks?(ast)
  end

  # Check if module is a protocol
  defp protocol?(ast) do
    case ast do
      {:defprotocol, _, _} -> true
      {:defimpl, _, _} -> true
      _ -> false
    end
  end

  # Check if module is a reporter
  defp reporter?(path) do
    String.contains?(path, "/reporter") or
      String.contains?(path, "/formatter")
  end

  # Check if AST contains `use` for a specific module
  defp has_use?(ast, module_name) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {:use, _, [{:__aliases__, _, parts} | _]}, _acc ->
          if List.last(parts) == module_name do
            {:ok, true}
          else
            {:ok, false}
          end

        node, acc ->
          {node, acc}
      end)

    found
  end

  # Check if AST has @callback directive
  defp has_callback?(ast, callback_name) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {:@, _, [{:callback, _, [{callback, _, _} | _]}]}, _acc ->
          if callback == callback_name do
            {:ok, true}
          else
            {:ok, false}
          end

        node, acc ->
          {node, acc}
      end)

    found
  end

  # Check if AST has @behaviour directive
  defp has_behaviour_directive?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {:@, _, [{:behaviour, _, _}]}, _acc ->
          {:ok, true}

        node, acc ->
          {node, acc}
      end)

    found
  end

  # Check if module defines many callbacks (likely a behaviour)
  defp has_many_callbacks?(ast) do
    {_, count} =
      Macro.prewalk(ast, 0, fn
        {:@, _, [{:callback, _, _}]}, acc ->
          {:ok, acc + 1}

        node, acc ->
          {node, acc}
      end)

    count >= 3
  end

  # Calculate priority score based on code characteristics
  defp calculate_score(ast, _path) do
    metrics = %{
      function_count: count_functions(ast),
      has_conditionals: has_conditionals?(ast),
      has_arithmetic: has_arithmetic?(ast),
      has_comparisons: has_comparisons?(ast),
      has_pattern_matching: has_pattern_matching?(ast),
      cyclomatic_complexity: estimate_complexity(ast)
    }

    # Score based on code characteristics
    base_score = 0

    # More functions = more logic to test
    base_score = base_score + min(metrics.function_count * 5, 30)

    # Conditionals indicate branching logic
    base_score = if metrics.has_conditionals, do: base_score + 20, else: base_score

    # Arithmetic/comparisons indicate computational logic
    base_score = if metrics.has_arithmetic, do: base_score + 15, else: base_score
    base_score = if metrics.has_comparisons, do: base_score + 15, else: base_score

    # Pattern matching indicates data transformation
    base_score = if metrics.has_pattern_matching, do: base_score + 10, else: base_score

    # Higher complexity = more value from mutation testing
    base_score = base_score + min(metrics.cyclomatic_complexity * 2, 20)

    min(base_score, 100)
  end

  # Count public and private function definitions
  defp count_functions(ast) do
    {_, count} =
      Macro.prewalk(ast, 0, fn
        {:def, _, _}, acc -> {:ok, acc + 1}
        {:defp, _, _}, acc -> {:ok, acc + 1}
        node, acc -> {node, acc}
      end)

    count
  end

  # Check for conditional statements
  defp has_conditionals?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {:if, _, _}, _acc -> {:ok, true}
        {:unless, _, _}, _acc -> {:ok, true}
        {:case, _, _}, _acc -> {:ok, true}
        {:cond, _, _}, _acc -> {:ok, true}
        node, acc -> {node, acc}
      end)

    found
  end

  # Check for arithmetic operations
  defp has_arithmetic?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {op, _, _}, _acc when op in [:+, :-, :*, :/] -> {:ok, true}
        node, acc -> {node, acc}
      end)

    found
  end

  # Check for comparison operations
  defp has_comparisons?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {op, _, _}, _acc when op in [:==, :!=, :<, :>, :<=, :>=, :===, :!==] -> {:ok, true}
        node, acc -> {node, acc}
      end)

    found
  end

  # Check for pattern matching (multiple function clauses)
  defp has_pattern_matching?(ast) do
    function_clauses =
      ast
      |> Macro.prewalk([], fn
        {:def, _, [{name, _, args} | _]}, acc when is_list(args) ->
          {nil, [{name, length(args)} | acc]}

        {:defp, _, [{name, _, args} | _]}, acc when is_list(args) ->
          {nil, [{name, length(args)} | acc]}

        node, acc ->
          {node, acc}
      end)
      |> elem(1)
      |> Enum.frequencies()
      |> Map.values()

    Enum.any?(function_clauses, &(&1 > 1))
  end

  # Estimate cyclomatic complexity (rough approximation)
  defp estimate_complexity(ast) do
    {_, count} =
      Macro.prewalk(ast, 0, fn
        {:if, _, _}, acc -> {:ok, acc + 1}
        {:unless, _, _}, acc -> {:ok, acc + 1}
        {:case, _, _}, acc -> {:ok, acc + 1}
        {:cond, _, _}, acc -> {:ok, acc + 1}
        {:and, _, _}, acc -> {:ok, acc + 1}
        {:or, _, _}, acc -> {:ok, acc + 1}
        {:&&, _, _}, acc -> {:ok, acc + 1}
        {:||, _, _}, acc -> {:ok, acc + 1}
        node, acc -> {node, acc}
      end)

    count
  end
end
