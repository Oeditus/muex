defmodule Muex.Mutator.WithClauseTest do
  use ExUnit.Case, async: true

  alias Muex.Mutator.WithClause

  defp arrow(pat, expr, line), do: {:<-, [line: line], [pat, expr]}

  defp with_node(args, line), do: {:with, [line: line], args}

  defp with_args(%{ast: {:with, _, args}}), do: args

  describe "mutate/2" do
    test "deletes each <- clause, keeping the do block" do
      a1 = arrow({:ok, {:a, [line: 1], nil}}, {:foo, [line: 1], []}, 1)
      a2 = arrow({:ok, {:b, [line: 1], nil}}, {:bar, [line: 1], []}, 1)
      kw = [do: {:+, [line: 2], [{:a, [line: 2], nil}, {:b, [line: 2], nil}]}]
      ast = with_node([a1, a2, kw], 1)

      mutations = WithClause.mutate(ast, %{file: "test.ex"})

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(with_args(&1) == [a2, kw]))
      assert Enum.any?(mutations, &(with_args(&1) == [a1, kw]))
    end

    test "only deletes <- clauses, never bare expressions" do
      bare = {:=, [line: 1], [{:x, [line: 1], nil}, 1]}
      a1 = arrow({:ok, {:a, [line: 1], nil}}, {:foo, [line: 1], []}, 1)
      a2 = arrow({:ok, {:b, [line: 1], nil}}, {:bar, [line: 1], []}, 1)
      kw = [do: {:a, [line: 2], nil}]
      ast = with_node([bare, a1, a2, kw], 1)

      mutations = WithClause.mutate(ast, %{file: "test.ex"})

      assert [_, _] = mutations

      for mutation <- mutations do
        args = with_args(mutation)
        assert bare in args
        assert kw in args
      end
    end

    test "produces descriptive labels referencing clause position" do
      a1 = arrow(:ok, {:foo, [line: 1], []}, 1)
      a2 = arrow(:ok, {:bar, [line: 1], []}, 1)
      ast = with_node([a1, a2, [do: :ok]], 1)

      mutations = WithClause.mutate(ast, %{file: "test.ex"})

      assert Enum.any?(mutations, &(&1.description == "WithClause: delete clause 1 of 2"))
      assert Enum.any?(mutations, &(&1.description == "WithClause: delete clause 2 of 2"))
    end

    test "does not mutate a with with a single <- clause" do
      ast = with_node([arrow(:ok, {:foo, [line: 1], []}, 1), [do: :ok]], 1)
      assert [] = WithClause.mutate(ast, %{file: "test.ex"})
    end

    test "includes proper metadata" do
      a1 = arrow(:ok, {:foo, [line: 10], []}, 10)
      a2 = arrow(:ok, {:bar, [line: 10], []}, 10)
      ast = with_node([a1, a2, [do: :ok]], 10)

      [mutation | _] = WithClause.mutate(ast, %{file: "lib/m.ex"})

      assert mutation.mutator == Muex.Mutator.WithClause
      assert mutation.location == %{file: "lib/m.ex", line: 10}
    end

    test "returns empty list for non-with AST" do
      assert [] = WithClause.mutate({:case, [line: 1], [:x, [do: []]]}, %{})
      assert [] = WithClause.mutate({:+, [line: 1], [:a, :b]}, %{})
    end
  end

  describe "name/0 and description/0" do
    test "name" do
      assert "WithClause" = WithClause.name()
    end

    test "description mentions with" do
      assert WithClause.description() =~ "with"
    end
  end

  describe "supported_languages/0" do
    test "supports Elixir" do
      assert Muex.Language.Elixir in WithClause.supported_languages()
    end
  end
end
