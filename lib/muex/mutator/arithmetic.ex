defmodule Muex.Mutator.Arithmetic do
  @moduledoc """
  Mutator for arithmetic operators.

  Applies mutations to arithmetic operations:
  - `+` <-> `-`
  - `*` <-> `/`
  - `+` -> `0` (remove addition)
  - `-` -> `0` (remove subtraction)
  """
  @behaviour Muex.Mutator
  @impl true
  def name do
    "Arithmetic"
  end

  @impl true
  def description do
    "Mutates arithmetic operators (+, -, *, /)"
  end

  @impl true
  def mutate(ast, context) do
    case ast do
      {:+, meta, [left, right]} = original_ast ->
        line = Keyword.get(meta, :line, 0)

        [
          build_mutation(original_ast, {:-, meta, [left, right]}, "+ to -", context, line),
          build_mutation(original_ast, 0, "+ to 0 (remove)", context, line)
        ]

      {:-, meta, [left, right]} = original_ast ->
        line = Keyword.get(meta, :line, 0)

        [
          build_mutation(original_ast, {:+, meta, [left, right]}, "- to +", context, line),
          build_mutation(original_ast, 0, "- to 0 (remove)", context, line)
        ]

      {:*, meta, [left, right]} = original_ast ->
        line = Keyword.get(meta, :line, 0)

        [
          build_mutation(original_ast, {:/, meta, [left, right]}, "* to /", context, line),
          build_mutation(original_ast, 1, "* to 1 (identity)", context, line)
        ]

      {:/, meta, [left, right]} = original_ast ->
        line = Keyword.get(meta, :line, 0)

        [
          build_mutation(original_ast, {:*, meta, [left, right]}, "/ to *", context, line),
          build_mutation(original_ast, 1, "/ to 1 (identity)", context, line)
        ]

      _ ->
        []
    end
  end

  defp build_mutation(original_ast, mutated_ast, description, context, line) do
    %{
      original_ast: original_ast,
      ast: mutated_ast,
      mutator: __MODULE__,
      description: "#{name()}: #{description}",
      location: %{file: Map.get(context, :file, "unknown"), line: line}
    }
  end
end
