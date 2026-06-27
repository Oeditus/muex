defmodule Muex.Reporter.Patch do
  @moduledoc """
  Builds a compact before/after snippet for a mutation.

  Reporters use this to show the actual code change introduced by each
  mutation, making survived or suspicious mutants easy to reproduce. Snippets
  are rendered from the mutation's `:original_ast` and `:ast` via
  `Macro.to_string/1`, falling back to `inspect/1` for abstract code that the
  Elixir formatter cannot stringify (e.g. Erlang forms).

  `of/1` returns `nil` when the mutation does not carry both the original and
  mutated AST, so callers can omit the patch gracefully.
  """

  @type t :: %{before: String.t(), after: String.t()}

  @doc """
  Returns a `%{before: ..., after: ...}` patch for a mutation.

  Returns `nil` when either `:original_ast` or `:ast` is missing.
  """
  @spec of(map()) :: t() | nil
  def of(mutation) do
    with {:ok, original} <- Map.fetch(mutation, :original_ast),
         {:ok, mutated} <- Map.fetch(mutation, :ast) do
      %{before: to_snippet(original), after: to_snippet(mutated)}
    else
      :error -> nil
    end
  end

  defp to_snippet(ast) do
    Macro.to_string(ast)
  rescue
    _ -> inspect(ast)
  end
end
