defmodule Muex.Mutator.BuildersTest do
  use ExUnit.Case, async: true

  alias Muex.Mutator.Builders

  # Existing mutator used only as a name source (name/0 -> "Comparison").
  @mutator Muex.Mutator.Comparison

  describe "build/5" do
    test "builds a mutation map with a name-prefixed description" do
      m = Builders.build(@mutator, {:x, [], nil}, "a to b", %{file: "lib/m.ex"}, 7)

      assert m.ast == {:x, [], nil}
      assert m.mutator == @mutator
      assert m.description == "Comparison: a to b"
      assert m.location == %{file: "lib/m.ex", line: 7}
    end

    test "defaults the file to \"unknown\"" do
      assert Builders.build(@mutator, :a, "d", %{}, 0).location.file == "unknown"
    end

    test "does not set :original_ast (walk/3 owns that field)" do
      refute Map.has_key?(Builders.build(@mutator, :a, "d", %{}, 1), :original_ast)
    end
  end

  describe "operator_swap/4" do
    @swaps %{<: :>=, >: :<=}

    test "swaps a binary operator present in the map, preserving args" do
      [m] = Builders.operator_swap({:<, [line: 3], [:a, :b]}, %{file: "f"}, @mutator, @swaps)
      assert m.ast == {:>=, [line: 3], [:a, :b]}
      assert m.description == "Comparison: < to >="
      assert m.location.line == 3
    end

    test "returns [] for operators not in the map" do
      assert [] = Builders.operator_swap({:==, [line: 1], [:a, :b]}, %{}, @mutator, @swaps)
    end

    test "returns [] for non-binary / unrelated AST" do
      assert [] = Builders.operator_swap({:<, [line: 1], [:a]}, %{}, @mutator, @swaps)
      assert [] = Builders.operator_swap({:foo, [], []}, %{}, @mutator, @swaps)
    end
  end

  describe "module_fn_swap/5" do
    @opposites %{put: :put_new, put_new: :put}

    defp call(mod, fun, line) do
      {{:., [line: line], [{:__aliases__, [line: line], [mod]}, fun]}, [line: line],
       [{:m, [line: line], nil}]}
    end

    test "swaps a module-qualified function, preserving module and args" do
      [m] = Builders.module_fn_swap(call(:Map, :put, 4), %{}, @mutator, [:Map], @opposites)
      assert {{:., _, [{:__aliases__, _, [:Map]}, :put_new]}, _, [{:m, _, nil}]} = m.ast
      assert m.description == "Comparison: Map.put to Map.put_new"
    end

    test "returns [] for modules not in the allow-list" do
      assert [] = Builders.module_fn_swap(call(:Enum, :put, 1), %{}, @mutator, [:Map], @opposites)
    end

    test "returns [] for functions without an opposite" do
      assert [] = Builders.module_fn_swap(call(:Map, :get, 1), %{}, @mutator, [:Map], @opposites)
    end

    test "returns [] for unrelated AST" do
      assert [] = Builders.module_fn_swap({:+, [], [:a, :b]}, %{}, @mutator, [:Map], @opposites)
    end
  end

  describe "clause_deletions/6" do
    test "produces one mutation per deletable position with N-of-M labels" do
      items = [:a, :b, :c]
      rebuild = fn remaining -> {:wrapped, remaining} end

      mutations = Builders.clause_deletions(@mutator, items, [0, 2], rebuild, %{file: "f"}, 5)

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:wrapped, [:b, :c]}))
      assert Enum.any?(mutations, &(&1.ast == {:wrapped, [:a, :b]}))
      assert Enum.any?(mutations, &(&1.description == "Comparison: delete clause 1 of 2"))
      assert Enum.any?(mutations, &(&1.description == "Comparison: delete clause 2 of 2"))
      assert Enum.all?(mutations, &(&1.location == %{file: "f", line: 5}))
    end
  end
end
