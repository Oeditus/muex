defmodule Muex.Compiler do
  @moduledoc """
  Compiles mutated ASTs and manages module hot-swapping.

  Uses the language adapter for converting AST to source and compiling modules.
  """

  @doc """
  Compiles a mutated AST and loads it into the BEAM.

  ## Parameters

    - `mutation` - The mutation map containing the mutated AST
    - `original_ast` - The original (complete) AST with mutation applied
    - `module_name` - The module name to compile
    - `language_adapter` - The language adapter module

  ## Returns

    - `{:ok, module}` - Successfully compiled and loaded module
    - `{:error, reason}` - Compilation failed
  """
  @spec compile(map(), term(), atom(), module()) :: {:ok, module()} | {:error, term()}
  def compile(mutation, original_ast, module_name, language_adapter) do
    # Replace the mutation point in the original AST
    mutated_full_ast = apply_mutation(original_ast, mutation)

    with {:ok, source} <- language_adapter.unparse(mutated_full_ast),
         {:ok, module} <- language_adapter.compile(source, module_name) do
      {:ok, module}
    end
  end

  @doc """
  Restores the original module by reloading it from disk.

  ## Parameters

    - `module_name` - The module to restore
    - `original_path` - Path to the original source file
    - `language_adapter` - The language adapter module

  ## Returns

    - `:ok` - Successfully restored
    - `{:error, reason}` - Restoration failed
  """
  @spec restore(atom(), String.t(), module()) :: :ok | {:error, term()}
  def restore(module_name, original_path, language_adapter) do
    with {:ok, source} <- File.read(original_path),
         {:ok, _module} <- language_adapter.compile(source, module_name) do
      :ok
    end
  end

  # Apply mutation to the AST by walking and replacing the mutation point
  defp apply_mutation(ast, _mutation) do
    # This is a simplified version - in production, we'd need to track
    # the exact location and context to replace the right node
    Macro.prewalk(ast, fn node ->
      # For now, we'll use a simple approach where we check if this node
      # matches a pattern we want to mutate
      node
    end)
  end
end
