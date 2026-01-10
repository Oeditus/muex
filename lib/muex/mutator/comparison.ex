defmodule Muex.Mutator.Comparison do
  @moduledoc """
  Mutator for comparison operators.

  Applies mutations to comparison operations:
  - `==` <-> `!=`
  - `>` <-> `<`
  - `>=` <-> `<=`
  - `===` <-> `!==`
  """

  @behaviour Muex.Mutator

  @impl true
  def name, do: "Comparison"

  @impl true
  def description, do: "Mutates comparison operators (==, !=, >, <, >=, <=)"

  @impl true
  def mutate(ast, context) do
    case ast do
      {:==, meta, args} ->
        [build_mutation({:!=, meta, args}, "== to !=", context, Keyword.get(meta, :line, 0))]

      {:!=, meta, args} ->
        [build_mutation({:==, meta, args}, "!= to ==", context, Keyword.get(meta, :line, 0))]

      {:>, meta, args} ->
        [
          build_mutation({:<, meta, args}, "> to <", context, Keyword.get(meta, :line, 0)),
          build_mutation({:>=, meta, args}, "> to >=", context, Keyword.get(meta, :line, 0))
        ]

      {:<, meta, args} ->
        [
          build_mutation({:>, meta, args}, "< to >", context, Keyword.get(meta, :line, 0)),
          build_mutation({:<=, meta, args}, "< to <=", context, Keyword.get(meta, :line, 0))
        ]

      {:>=, meta, args} ->
        [
          build_mutation({:<=, meta, args}, ">= to <=", context, Keyword.get(meta, :line, 0)),
          build_mutation({:>, meta, args}, ">= to >", context, Keyword.get(meta, :line, 0))
        ]

      {:<=, meta, args} ->
        [
          build_mutation({:>=, meta, args}, "<= to >=", context, Keyword.get(meta, :line, 0)),
          build_mutation({:<, meta, args}, "<= to <", context, Keyword.get(meta, :line, 0))
        ]

      {:===, meta, args} ->
        [build_mutation({:!==, meta, args}, "=== to !==", context, Keyword.get(meta, :line, 0))]

      {:!==, meta, args} ->
        [build_mutation({:===, meta, args}, "!== to ===", context, Keyword.get(meta, :line, 0))]

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
