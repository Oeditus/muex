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
        def test_file_pattern, do: ~r/_test\\.mylang$/
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
end
