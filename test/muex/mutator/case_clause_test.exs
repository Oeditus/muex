defmodule Muex.Mutator.CaseClauseTest do
  use ExUnit.Case, async: true

  alias Muex.Mutator.CaseClause

  defp clause(pattern, body, line), do: {:->, [line: line], [[pattern], body]}

  defp case_node(clauses, line) do
    {:case, [line: line], [{:x, [line: line], nil}, [do: clauses]]}
  end

  defp do_clauses(%{ast: {:case, _, [_subject, [do: clauses]]}}), do: clauses

  describe "mutate/2" do
    test "produces one mutation per clause, each dropping that clause" do
      c1 = clause(1, :one, 1)
      c2 = clause({:_, [line: 1], nil}, :other, 1)
      ast = case_node([c1, c2], 1)

      mutations = CaseClause.mutate(ast, %{file: "test.ex"})

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(do_clauses(&1) == [c2]))
      assert Enum.any?(mutations, &(do_clauses(&1) == [c1]))
    end

    test "preserves the case subject" do
      ast = case_node([clause(1, :one, 3), clause(2, :two, 3)], 3)

      [mutation | _] = CaseClause.mutate(ast, %{file: "test.ex"})

      assert {:case, _, [{:x, _, nil}, [do: _]]} = mutation.ast
    end

    test "produces descriptive labels referencing clause position" do
      ast = case_node([clause(1, :one, 1), clause(2, :two, 1)], 1)

      mutations = CaseClause.mutate(ast, %{file: "test.ex"})

      assert Enum.any?(mutations, &(&1.description == "CaseClause: delete clause 1 of 2"))
      assert Enum.any?(mutations, &(&1.description == "CaseClause: delete clause 2 of 2"))
    end

    test "does not mutate a case with a single clause" do
      ast = case_node([clause(1, :one, 1)], 1)
      assert [] = CaseClause.mutate(ast, %{file: "test.ex"})
    end

    test "includes proper metadata" do
      ast = case_node([clause(1, :one, 10), clause(2, :two, 10)], 10)

      [mutation | _] = CaseClause.mutate(ast, %{file: "lib/m.ex"})

      assert mutation.mutator == Muex.Mutator.CaseClause
      assert mutation.location == %{file: "lib/m.ex", line: 10}
    end

    test "returns empty list for non-case AST" do
      assert [] = CaseClause.mutate({:+, [line: 1], [:a, :b]}, %{})
    end
  end

  describe "name/0 and description/0" do
    test "name" do
      assert "CaseClause" = CaseClause.name()
    end

    test "description mentions case" do
      assert CaseClause.description() =~ "case"
    end
  end

  describe "supported_languages/0" do
    test "supports Elixir" do
      assert Muex.Language.Elixir in CaseClause.supported_languages()
    end
  end
end
