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
  def name, do: "Arithmetic"

  @impl true
  def description, do: "Mutates arithmetic operators (+, -, *, /)"

  @impl true
  def mutate(ast, context) do
    case ast do
      {:+, meta, [left, right]} ->
        line = Keyword.get(meta, :line, 0)

        [
          build_mutation({:-, meta, [left, right]}, "+ to -", context, line),
          build_mutation(0, "+ to 0 (remove)", context, line)
        ]

      {:-, meta, [left, right]} ->
        line = Keyword.get(meta, :line, 0)

        [
          build_mutation({:+, meta, [left, right]}, "- to +", context, line),
          build_mutation(0, "- to 0 (remove)", context, line)
        ]

      {:*, meta, [left, right]} ->
        line = Keyword.get(meta, :line, 0)

        [
          build_mutation({:/, meta, [left, right]}, "* to /", context, line),
          build_mutation(1, "* to 1 (identity)", context, line)
        ]

      {:/, meta, [left, right]} ->
        line = Keyword.get(meta, :line, 0)

        [
          build_mutation({:*, meta, [left, right]}, "/ to *", context, line),
          build_mutation(1, "/ to 1 (identity)", context, line)
        ]

      _ ->
        []
    end
  end

  defp build_mutation(mutated_ast, description, context, line) do
    %{
      ast: mutated_ast,
      mutator: __MODULE__,
      description: "#{name()}: #{description}",
      location: %{
        file: Map.get(context, :file, "unknown"),
        line: line
      }
    }
  end
end
