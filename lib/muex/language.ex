defmodule Muex.Language do
  @moduledoc """
  Behaviour for language adapters that provide AST parsing, unparsing, and compilation.

  This behaviour defines the interface for supporting different programming languages
  in mutation testing. Each language adapter implements the callbacks to handle
  language-specific AST operations.

  ## Example

      defmodule Muex.Language.MyLanguage do
        @behaviour Muex.Language

        @impl true
        def parse(source), do: {:ok, parse_to_ast(source)}

        @impl true
        def unparse(ast), do: {:ok, ast_to_string(ast)}

        @impl true
        def compile(source, module_name), do: {:ok, compiled_module}

        @impl true
        def file_extensions, do: [".my"]

        @impl true
        def test_file_pattern, do: ~r/_test\.my$/
      end
  """
  @doc """
  Parses source code into an Abstract Syntax Tree (AST).

  ## Parameters

    - `source` - String containing the source code to parse

  ## Returns

    - `{:ok, ast}` - Successfully parsed AST (term structure depends on language)
    - `{:error, reason}` - Parsing failed with error details
  """
  @callback parse(source :: String.t()) :: {:ok, ast :: term()} | {:error, term()}
  @doc """
  Converts an AST back into source code string.

  ## Parameters

    - `ast` - The AST to convert back to source code

  ## Returns

    - `{:ok, source}` - Successfully generated source code
    - `{:error, reason}` - Unparsing failed with error details
  """
  @callback unparse(ast :: term()) :: {:ok, String.t()} | {:error, term()}
  @doc """
  Compiles source code into a module that can be loaded into the BEAM.

  ## Parameters

    - `source` - String containing the source code to compile
    - `module_name` - Atom representing the module name

  ## Returns

    - `{:ok, module}` - Successfully compiled module
    - `{:error, reason}` - Compilation failed with error details
  """
  @callback compile(source :: String.t(), module_name :: atom()) ::
              {:ok, module()} | {:error, term()}
  @doc """
  Returns the list of file extensions for this language.

  ## Returns

    List of file extensions including the dot (e.g., `[".ex", ".exs"]`)
  """
  @callback file_extensions() :: [String.t()]
  @doc """
  Returns a regex pattern to identify test files.

  ## Returns

    Regex that matches test file paths
  """
  @callback test_file_pattern() :: Regex.t()
end
