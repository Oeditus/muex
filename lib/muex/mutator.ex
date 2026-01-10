defmodule Muex.Mutator do
  @moduledoc """
  Behaviour for mutation operators that transform AST nodes.

  Mutators implement specific mutation strategies (e.g., arithmetic operators,
  boolean operators, literals) and return a list of possible mutations for a given AST.

  Each mutator is language-agnostic and works with the raw AST structure provided
  by the language adapter.

  ## Example

      defmodule Muex.Mutator.MyMutator do
        @behaviour Muex.Mutator

        @impl true
        def mutate(ast, _context) do
          # Return list of mutated AST variants
          [mutated_ast_1, mutated_ast_2]
        end

        @impl true
        def name, do: "My Mutator"

        @impl true
        def description, do: "Mutates specific AST patterns"
      end
  """

  @typedoc """
  Represents a single mutation with its metadata.
  """
  @type mutation :: %{
          ast: term(),
          mutator: module(),
          description: String.t(),
          location: %{file: String.t(), line: non_neg_integer()}
        }

  @doc """
  Applies mutations to the given AST.

  ## Parameters

    - `ast` - The AST to mutate
    - `context` - Map containing additional context (file path, line number, etc.)

  ## Returns

    List of `mutation` maps, each representing a possible mutation
  """
  @callback mutate(ast :: term(), context :: map()) :: [mutation()]

  @doc """
  Returns the name of the mutator.

  ## Returns

    String name identifying this mutator
  """
  @callback name() :: String.t()

  @doc """
  Returns a description of what this mutator does.

  ## Returns

    String describing the mutation strategy
  """
  @callback description() :: String.t()

  @doc """
  Walks through an AST and applies all registered mutators.

  ## Parameters

    - `ast` - The AST to traverse
    - `mutators` - List of mutator modules to apply
    - `context` - Context map with file information

  ## Returns

    List of all possible mutations found in the AST
  """
  @spec walk(ast :: term(), mutators :: [module()], context :: map()) :: [mutation()]
  def walk(ast, mutators, context) do
    {_ast, mutations} =
      Macro.prewalk(ast, [], fn node, acc ->
        node_mutations =
          Enum.flat_map(mutators, fn mutator ->
            mutator.mutate(node, context)
          end)

        {node, acc ++ node_mutations}
      end)

    mutations
  end
end
