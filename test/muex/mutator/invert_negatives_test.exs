defmodule Muex.Mutator.InvertNegativesTest do
  use ExUnit.Case, async: true

  alias Muex.Mutator.InvertNegatives

  describe "mutate/2" do
    test "inverts unary negation of a variable (-x -> x)" do
      operand = {:x, [line: 1], nil}
      ast = {:-, [line: 1], [operand]}
      context = %{file: "test.ex"}

      mutations = InvertNegatives.mutate(ast, context)

      assert [mutation] = mutations
      assert mutation.ast == operand
    end

    test "inverts unary negation of a nested expression" do
      operand = {:+, [line: 2], [{:a, [line: 2], nil}, {:b, [line: 2], nil}]}
      ast = {:-, [line: 2], [operand]}
      context = %{file: "test.ex"}

      [mutation] = InvertNegatives.mutate(ast, context)

      assert mutation.ast == operand
    end

    test "produces a descriptive label" do
      ast = {:-, [line: 3], [{:n, [line: 3], nil}]}
      context = %{file: "test.ex"}

      [mutation] = InvertNegatives.mutate(ast, context)

      assert mutation.description == "InvertNegatives: -x to x"
    end

    test "includes proper metadata in mutations" do
      ast = {:-, [line: 10], [{:value, [line: 10], nil}]}
      context = %{file: "lib/my_module.ex"}

      [mutation] = InvertNegatives.mutate(ast, context)

      assert mutation.mutator == Muex.Mutator.InvertNegatives
      assert mutation.location.file == "lib/my_module.ex"
      assert mutation.location.line == 10
    end

    test "ignores binary subtraction (a - b)" do
      ast = {:-, [line: 4], [{:a, [line: 4], nil}, {:b, [line: 4], nil}]}
      context = %{file: "test.ex"}

      assert [] = InvertNegatives.mutate(ast, context)
    end

    test "ignores unary plus" do
      ast = {:+, [line: 5], [{:x, [line: 5], nil}]}
      context = %{file: "test.ex"}

      assert [] = InvertNegatives.mutate(ast, context)
    end

    test "returns empty list for unrelated operators" do
      ast = {:foo, [], []}
      context = %{}

      assert [] = InvertNegatives.mutate(ast, context)
    end
  end

  describe "name/0" do
    test "returns mutator name" do
      assert "InvertNegatives" = InvertNegatives.name()
    end
  end

  describe "description/0" do
    test "returns mutator description" do
      desc = InvertNegatives.description()
      assert is_binary(desc)
      assert desc =~ "negat"
    end
  end

  describe "supported_languages/0" do
    test "supports Elixir" do
      assert Muex.Language.Elixir in InvertNegatives.supported_languages()
    end
  end
end
