defmodule Muex.Mutator.WithClause do
  @moduledoc """
  Elixir-specific mutator that deletes a `<-` clause from a `with` expression.

  For a `with` containing two or more `<-` clauses, produces one mutation per
  `<-` clause that removes it while preserving the `do`/`else` block and any
  bare (non-`<-`) expressions.

  Some deletions may produce code that no longer compiles (a later clause or the
  body referencing the deleted binding); those are reported as invalid mutants
  by the runner rather than survivors. A clause whose removal compiles *and*
  passes the suite points at a `with` step the tests do not depend on.
  """

  @behaviour Muex.Mutator

  alias Muex.Mutator.Builders

  @impl true
  def name, do: "WithClause"

  @impl true
  def description, do: "Deletes a <- clause from a with expression"

  @impl true
  def supported_languages, do: [Muex.Language.Elixir]

  @impl true
  def mutate({:with, meta, args}, context) when is_list(args) and length(args) >= 2 do
    block = List.last(args)
    leading = Enum.drop(args, -1)

    arrow_positions =
      leading
      |> Enum.with_index()
      |> Enum.filter(fn {clause, _index} -> match?({:<-, _, _}, clause) end)
      |> Enum.map(fn {_clause, index} -> index end)

    if block_with_do?(block) and length(arrow_positions) >= 2 do
      rebuild = fn remaining -> {:with, meta, remaining ++ [block]} end

      Builders.clause_deletions(
        __MODULE__,
        leading,
        arrow_positions,
        rebuild,
        context,
        Keyword.get(meta, :line, 0)
      )
    else
      []
    end
  end

  def mutate(_ast, _context), do: []

  defp block_with_do?(block), do: Keyword.keyword?(block) and Keyword.has_key?(block, :do)
end
