defmodule Muex.DependencyAnalyzer do
  @moduledoc """
  Analyzes test files to determine which tests depend on which modules.

  Builds a dependency graph by parsing test files and extracting module references.
  This allows running only the tests that are affected by a specific mutation.
  """

  @type dependency_map :: %{module() => [Path.t()]}

  @doc """
  Analyzes test files and builds a dependency map.

  ## Parameters

    - `test_dir` - Directory containing test files (default: "test")

  ## Returns

    Map of module atoms to list of test file paths that reference them.

  ## Examples

      iex> analyze("test")
      %{MyModule => ["test/my_module_test.exs"], ...}
  """
  @spec analyze(Path.t()) :: dependency_map()
  def analyze(test_dir \\ "test") do
    test_dir
    |> find_test_files()
    |> Enum.reduce(%{}, fn test_file, acc ->
      modules = extract_module_dependencies(test_file)

      Enum.reduce(modules, acc, fn module, acc_inner ->
        Map.update(acc_inner, module, [test_file], fn existing ->
          [test_file | existing] |> Enum.uniq()
        end)
      end)
    end)
  end

  @doc """
  Gets test files that depend on a specific module.

  ## Parameters

    - `module_name` - The module to find tests for
    - `dependency_map` - The dependency map from `analyze/1`

  ## Returns

    List of test file paths that depend on the module.
  """
  @spec get_dependent_tests(module(), dependency_map()) :: [Path.t()]
  def get_dependent_tests(module_name, dependency_map) do
    Map.get(dependency_map, module_name, [])
  end

  @doc """
  Gets test files for a mutation based on the mutated module.

  ## Parameters

    - `mutation` - The mutation map containing location info
    - `dependency_map` - The dependency map from `analyze/1`
    - `file_to_module` - Map of file paths to module names

  ## Returns

    List of test file paths to execute for this mutation.
  """
  @spec get_tests_for_mutation(map(), dependency_map(), %{Path.t() => module()}) :: [Path.t()]
  def get_tests_for_mutation(mutation, dependency_map, file_to_module) do
    file_path = mutation.location.file

    case Map.get(file_to_module, file_path) do
      nil -> []
      module_name -> get_dependent_tests(module_name, dependency_map)
    end
  end

  # Find all test files in directory
  defp find_test_files(test_dir) do
    pattern = Path.join([test_dir, "**", "*_test.exs"])
    Path.wildcard(pattern)
  end

  # Extract module dependencies from a test file
  defp extract_module_dependencies(test_file) do
    case File.read(test_file) do
      {:ok, content} ->
        content
        |> Code.string_to_quoted()
        |> case do
          {:ok, ast} -> extract_modules_from_ast(ast)
          {:error, _} -> []
        end

      {:error, _} ->
        []
    end
  end

  # Walk AST and extract module references
  @dialyzer {:nowarn_function, extract_modules_from_ast: 1}
  @spec extract_modules_from_ast(Macro.t()) :: [Macro.t()]
  defp extract_modules_from_ast(ast) do
    {_ast, modules} =
      Macro.prewalk(ast, MapSet.new(), fn node, acc ->
        modules = extract_module_from_node(node)
        {node, MapSet.union(acc, modules)}
      end)

    MapSet.to_list(modules)
  end

  # Extract module names from different AST node patterns
  defp extract_module_from_node(node) do
    case node do
      # alias MyModule
      {:alias, _, [{:__aliases__, _, parts}]} ->
        MapSet.new([module_from_parts(parts)])

      # alias MyModule.SubModule
      {:alias, _, [{:__aliases__, _, parts}, _opts]} ->
        MapSet.new([module_from_parts(parts)])

      # import MyModule
      {:import, _, [{:__aliases__, _, parts}]} ->
        MapSet.new([module_from_parts(parts)])

      # import MyModule, only: [...]
      {:import, _, [{:__aliases__, _, parts}, _opts]} ->
        MapSet.new([module_from_parts(parts)])

      # MyModule.function()
      {{:., _, [{:__aliases__, _, parts}, _function]}, _, _args} ->
        MapSet.new([module_from_parts(parts)])

      # describe "MyModule" - extract from string if it looks like a module
      {:describe, _, [module_string, _block]} when is_binary(module_string) ->
        extract_module_from_string(module_string)

      # test "MyModule.function" - extract from string if it looks like a module
      {:test, _, [test_name, _block]} when is_binary(test_name) ->
        extract_module_from_string(test_name)

      _ ->
        MapSet.new()
    end
  end

  # Try to extract module name from a string (e.g., "MyModule.function")
  defp extract_module_from_string(str) do
    case Regex.run(~r/^([A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*)/, str) do
      [_, module_str] ->
        try do
          module = String.to_existing_atom("Elixir." <> module_str)
          MapSet.new([module])
        rescue
          ArgumentError -> MapSet.new()
        end

      nil ->
        MapSet.new()
    end
  end

  # Convert alias parts to module atom
  defp module_from_parts(parts) do
    parts
    |> Enum.map_join(".", &to_string/1)
    |> then(&("Elixir." <> &1))
    |> String.to_atom()
  end
end
