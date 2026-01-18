defmodule Muex.Mutator.Boolean do
  @moduledoc """
  Mutator for boolean operators and literals.

  Applies mutations to boolean operations:
  - `and` <-> `or`
  - `&&` <-> `||`
  - `true` <-> `false`
  - Remove negation: `not x` -> `x`
  """
  @behaviour Muex.Mutator
  @impl true
  def name do
    "Boolean"
  end

  @impl true
  def description do
    "Mutates boolean operators (and, or, &&, ||, not) and literals (true, false)"
  end

  @impl true
  def mutate(ast, context) do
    case ast do
      {:and, meta, args} ->
        [build_mutation({:or, meta, args}, "and to or", context, Keyword.get(meta, :line, 0))]

      {:or, meta, args} ->
        [build_mutation({:and, meta, args}, "or to and", context, Keyword.get(meta, :line, 0))]

      {:&&, meta, args} ->
        [build_mutation({:||, meta, args}, "&& to ||", context, Keyword.get(meta, :line, 0))]

      {:||, meta, args} ->
        [build_mutation({:&&, meta, args}, "|| to &&", context, Keyword.get(meta, :line, 0))]

      true ->
        [build_mutation(false, "true to false", context, 0)]

      false ->
        [build_mutation(true, "false to true", context, 0)]

      {:not, meta, [arg]} ->
        line = Keyword.get(meta, :line, 0)
        [build_mutation(arg, "remove not (not x to x)", context, line)]

      _ ->
        []
    end
  end

  defp build_mutation(mutated_ast, description, context, line) do
    %{
      ast: mutated_ast,
      mutator: __MODULE__,
      description: "#{name()}: #{description}",
      location: %{file: Map.get(context, :file, "unknown"), line: line}
    }
  end
end
