defmodule Muex.Mutator.ArithmeticTest do
  use ExUnit.Case, async: true

  alias Muex.Mutator.Arithmetic

  describe "mutate/2" do
    test "mutates addition operator" do
      ast = {:+, [line: 1], [:a, :b]}
      context = %{file: "test.ex"}

      mutations = Arithmetic.mutate(ast, context)

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:-, [line: 1], [:a, :b]}))
      assert Enum.any?(mutations, &(&1.ast == 0))
    end

    test "mutates subtraction operator" do
      ast = {:-, [line: 2], [:x, :y]}
      context = %{file: "test.ex"}

      mutations = Arithmetic.mutate(ast, context)

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:+, [line: 2], [:x, :y]}))
    end

    test "mutates multiplication operator" do
      ast = {:*, [line: 3], [:m, :n]}
      context = %{file: "test.ex"}

      mutations = Arithmetic.mutate(ast, context)

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:/, [line: 3], [:m, :n]}))
      assert Enum.any?(mutations, &(&1.ast == 1))
    end

    test "returns empty list for non-arithmetic operators" do
      ast = {:foo, [], []}
      context = %{}

      assert [] = Arithmetic.mutate(ast, context)
    end
  end

  describe "name/0" do
    test "returns mutator name" do
      assert "Arithmetic" = Arithmetic.name()
    end
  end
end
