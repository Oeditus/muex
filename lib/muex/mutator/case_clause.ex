defmodule Muex.Mutator.CaseClause do
  @moduledoc """
  Elixir-specific mutator that deletes a clause from a `case` expression.

  For a `case` with two or more clauses, produces one mutation per clause that
  removes that clause from the branch list. Cases with a single clause are left
  untouched (there is nothing to delete).

  Like `StatementDeletion`, this is a high-value operator: if removing a branch
  doesn't fail any test, that branch is either unreachable or its behaviour is
  unasserted. Patterns and bodies *within* surviving clauses are still mutated
  independently by their own mutators via `walk/3`.
  """

  @behaviour Muex.Mutator

  alias Muex.Mutator.Builders

  @impl true
  def name, do: "CaseClause"

  @impl true
  def description, do: "Deletes a clause from a case expression"

  @impl true
  def supported_languages, do: [Muex.Language.Elixir]

  @impl true
  def mutate({:case, meta, [subject, [do: clauses]]}, context)
      when is_list(clauses) and length(clauses) >= 2 do
    rebuild = fn remaining -> {:case, meta, [subject, [do: remaining]]} end
    positions = Enum.to_list(0..(length(clauses) - 1))

    Builders.clause_deletions(
      __MODULE__,
      clauses,
      positions,
      rebuild,
      context,
      Keyword.get(meta, :line, 0)
    )
  end

  def mutate(_ast, _context), do: []
end
