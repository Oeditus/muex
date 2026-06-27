defmodule Muex.Mutator.CondClause do
  @moduledoc """
  Elixir-specific mutator that deletes a clause from a `cond` expression.

  For a `cond` with two or more clauses, produces one mutation per clause that
  removes it from the branch list. Single-clause `cond`s are left untouched.

  Companion to `CaseClause`: a surviving mutant means a `cond` branch is either
  unreachable or its selection is unasserted. Conditions and bodies within
  surviving clauses are still mutated independently by `walk/3`.
  """

  @behaviour Muex.Mutator

  alias Muex.Mutator.Builders

  @impl true
  def name, do: "CondClause"

  @impl true
  def description, do: "Deletes a clause from a cond expression"

  @impl true
  def supported_languages, do: [Muex.Language.Elixir]

  @impl true
  def mutate({:cond, meta, [[do: clauses]]}, context)
      when is_list(clauses) and length(clauses) >= 2 do
    rebuild = fn remaining -> {:cond, meta, [[do: remaining]]} end
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
