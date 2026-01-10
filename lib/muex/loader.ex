defmodule Muex.Loader do
  @moduledoc """
  Loads and parses source files using a language adapter.

  The loader discovers source files, filters out test files and other
  unwanted patterns, and parses them into ASTs using the provided language adapter.
  """

  @type file_entry :: %{
          path: String.t(),
          ast: term(),
          module_name: atom() | nil
        }

  @doc """
  Loads source files from the given directory using the language adapter.

  ## Parameters

    - `directory` - Root directory to scan for source files
    - `language_adapter` - Module implementing `Muex.Language` behaviour
    - `opts` - Options:
      - `:include` - List of glob patterns to include (default: all files with adapter's extensions)
      - `:exclude` - List of patterns to exclude (default: test files)

  ## Returns

    `{:ok, files}` where files is a list of `file_entry` maps
  """
  @spec load(String.t(), module(), keyword()) :: {:ok, [file_entry()]} | {:error, term()}
  def load(directory, language_adapter, opts \\ []) do
    extensions = language_adapter.file_extensions()
    test_pattern = language_adapter.test_file_pattern()

    exclude_patterns = Keyword.get(opts, :exclude, [test_pattern])

    files =
      directory
      |> discover_files(extensions)
      |> Enum.reject(&excluded?(&1, exclude_patterns))
      |> Enum.map(&parse_file(&1, language_adapter))
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, entry} -> entry end)

    {:ok, files}
  end

  defp discover_files(directory, extensions) do
    extensions
    |> Enum.flat_map(fn ext ->
      Path.wildcard(Path.join([directory, "**", "*#{ext}"]))
    end)
    |> Enum.uniq()
  end

  defp excluded?(path, patterns) do
    Enum.any?(patterns, fn
      %Regex{} = pattern -> Regex.match?(pattern, path)
      string when is_binary(string) -> String.contains?(path, string)
    end)
  end

  defp parse_file(path, language_adapter) do
    with {:ok, source} <- File.read(path),
         {:ok, ast} <- language_adapter.parse(source) do
      module_name = extract_module_name(ast)

      {:ok,
       %{
         path: path,
         ast: ast,
         module_name: module_name
       }}
    end
  end

  defp extract_module_name(ast) do
    case ast do
      {:defmodule, _meta, [{:__aliases__, _, name_parts} | _]} ->
        Module.concat(name_parts)

      _ ->
        nil
    end
  end
end
