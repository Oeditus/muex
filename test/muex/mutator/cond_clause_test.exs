defmodule Muex.Mutator.CondClauseTest do
  use ExUnit.Case, async: true

  alias Muex.Mutator.CondClause

  defp clause(condition, body, line), do: {:->, [line: line], [[condition], body]}

  defp cond_node(clauses, line), do: {:cond, [line: line], [[do: clauses]]}

  defp do_clauses(%{ast: {:cond, _, [[do: clauses]]}}), do: clauses

  describe "mutate/2" do
    test "produces one mutation per clause, each dropping that clause" do
      c1 = clause({:>, [line: 1], [:a, :b]}, :first, 1)
      c2 = clause(true, :default, 1)
      ast = cond_node([c1, c2], 1)

      mutations = CondClause.mutate(ast, %{file: "test.ex"})

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(do_clauses(&1) == [c2]))
      assert Enum.any?(mutations, &(do_clauses(&1) == [c1]))
    end

    test "produces descriptive labels referencing clause position" do
      ast = cond_node([clause(true, :a, 1), clause(true, :b, 1)], 1)

      mutations = CondClause.mutate(ast, %{file: "test.ex"})

      assert Enum.any?(mutations, &(&1.description == "CondClause: delete clause 1 of 2"))
      assert Enum.any?(mutations, &(&1.description == "CondClause: delete clause 2 of 2"))
    end

    test "does not mutate a cond with a single clause" do
      ast = cond_node([clause(true, :only, 1)], 1)
      assert [] = CondClause.mutate(ast, %{file: "test.ex"})
    end

    test "includes proper metadata" do
      ast = cond_node([clause(true, :a, 10), clause(true, :b, 10)], 10)

      [mutation | _] = CondClause.mutate(ast, %{file: "lib/m.ex"})

      assert mutation.mutator == Muex.Mutator.CondClause
      assert mutation.location == %{file: "lib/m.ex", line: 10}
    end

    test "returns empty list for non-cond AST" do
      assert [] = CondClause.mutate({:case, [line: 1], [:x, [do: []]]}, %{})
      assert [] = CondClause.mutate({:+, [line: 1], [:a, :b]}, %{})
    end
  end

  describe "name/0 and description/0" do
    test "name" do
      assert "CondClause" = CondClause.name()
    end

    test "description mentions cond" do
      assert CondClause.description() =~ "cond"
    end
  end

  describe "supported_languages/0" do
    test "supports Elixir" do
      assert Muex.Language.Elixir in CondClause.supported_languages()
    end
  end
end
