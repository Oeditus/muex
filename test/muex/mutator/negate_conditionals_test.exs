defmodule Muex.Mutator.NegateConditionalsTest do
  use ExUnit.Case, async: true

  alias Muex.Mutator.NegateConditionals

  describe "mutate/2" do
    test "negates < to >= (logical complement)" do
      ast = {:<, [line: 1], [:a, :b]}
      [mutation] = NegateConditionals.mutate(ast, %{file: "test.ex"})
      assert mutation.ast == {:>=, [line: 1], [:a, :b]}
      assert mutation.description == "NegateConditionals: < to >="
    end

    test "negates > to <=" do
      ast = {:>, [line: 2], [:a, :b]}
      [mutation] = NegateConditionals.mutate(ast, %{file: "test.ex"})
      assert mutation.ast == {:<=, [line: 2], [:a, :b]}
    end

    test "negates <= to >" do
      ast = {:<=, [line: 3], [:a, :b]}
      [mutation] = NegateConditionals.mutate(ast, %{file: "test.ex"})
      assert mutation.ast == {:>, [line: 3], [:a, :b]}
    end

    test "negates >= to <" do
      ast = {:>=, [line: 4], [:a, :b]}
      [mutation] = NegateConditionals.mutate(ast, %{file: "test.ex"})
      assert mutation.ast == {:<, [line: 4], [:a, :b]}
    end

    test "covers all relational operators with single complement each" do
      for {op, complement} <- [{:<, :>=}, {:>, :<=}, {:<=, :>}, {:>=, :<}] do
        ast = {op, [line: 1], [:a, :b]}
        mutations = NegateConditionals.mutate(ast, %{file: "test.ex"})
        assert [%{ast: {^complement, [line: 1], [:a, :b]}}] = mutations
      end
    end

    test "includes proper metadata" do
      ast = {:<, [line: 10], [:a, :b]}
      [mutation] = NegateConditionals.mutate(ast, %{file: "lib/m.ex"})
      assert mutation.mutator == Muex.Mutator.NegateConditionals
      assert mutation.location == %{file: "lib/m.ex", line: 10}
    end

    test "ignores equality operators (left to Comparison mutator)" do
      assert [] = NegateConditionals.mutate({:==, [line: 1], [:a, :b]}, %{})
      assert [] = NegateConditionals.mutate({:!=, [line: 1], [:a, :b]}, %{})
      assert [] = NegateConditionals.mutate({:===, [line: 1], [:a, :b]}, %{})
      assert [] = NegateConditionals.mutate({:!==, [line: 1], [:a, :b]}, %{})
    end

    test "returns empty list for unrelated operators" do
      assert [] = NegateConditionals.mutate({:+, [line: 1], [:a, :b]}, %{})
    end
  end

  describe "name/0 and description/0" do
    test "name" do
      assert "NegateConditionals" = NegateConditionals.name()
    end

    test "description" do
      assert NegateConditionals.description() =~ "complement"
    end
  end

  describe "supported_languages/0" do
    test "supports Elixir" do
      assert Muex.Language.Elixir in NegateConditionals.supported_languages()
    end
  end
end
