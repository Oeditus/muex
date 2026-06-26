defmodule Muex.Mutator.FunctionCallTest do
  use ExUnit.Case, async: true

  alias Muex.Mutator.FunctionCall

  describe "mutate/2 - local function calls" do
    test "removes single argument function call" do
      ast = {:foo, [line: 1], [:arg]}
      context = %{file: "test.ex"}

      mutations = FunctionCall.mutate(ast, context)

      assert [_] = mutations
      assert Enum.any?(mutations, &(&1.ast == nil))
    end

    test "removes and swaps two argument function call" do
      ast = {:foo, [line: 2], [:a, :b]}
      context = %{file: "test.ex"}

      mutations = FunctionCall.mutate(ast, context)

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(&1.ast == nil))
      assert Enum.any?(mutations, &(&1.ast == {:foo, [line: 2], [:b, :a]}))
    end

    test "swaps first two arguments in three argument call" do
      ast = {:foo, [line: 3], [:a, :b, :c]}
      context = %{file: "test.ex"}

      mutations = FunctionCall.mutate(ast, context)

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:foo, [line: 3], [:b, :a, :c]}))
    end

    test "does not mutate special forms like def" do
      ast = {:def, [line: 1], [:foo, :bar]}
      context = %{file: "test.ex"}

      mutations = FunctionCall.mutate(ast, context)

      assert [] = mutations
    end

    test "does not mutate defmodule" do
      ast = {:defmodule, [line: 1], [:Foo, :bar]}
      context = %{file: "test.ex"}

      mutations = FunctionCall.mutate(ast, context)

      assert [] = mutations
    end

    test "does not mutate if" do
      ast = {:if, [line: 1], [:condition, :body]}
      context = %{file: "test.ex"}

      mutations = FunctionCall.mutate(ast, context)

      assert [] = mutations
    end

    test "does not mutate unless" do
      ast = {:unless, [line: 1], [:condition, :body]}
      context = %{file: "test.ex"}

      mutations = FunctionCall.mutate(ast, context)

      assert [] = mutations
    end

    test "does not mutate case" do
      ast = {:case, [line: 1], [:expr, :clauses]}
      context = %{file: "test.ex"}

      mutations = FunctionCall.mutate(ast, context)

      assert [] = mutations
    end

    test "does not mutate -> clause arrows (case/fn/cond clauses)" do
      ast = {:->, [line: 1], [[:pattern], :body]}
      context = %{file: "test.ex"}

      mutations = FunctionCall.mutate(ast, context)

      assert [] = mutations
    end

    test "does not mutate <- clauses (with/comprehension clauses)" do
      ast = {:<-, [line: 1], [:pattern, :expr]}
      context = %{file: "test.ex"}

      mutations = FunctionCall.mutate(ast, context)

      assert [] = mutations
    end
  end

  describe "mutate/2 - remote function calls" do
    test "removes remote function call" do
      ast = {{:., [], [String, :upcase]}, [line: 5], ["hello"]}
      context = %{file: "test.ex"}

      mutations = FunctionCall.mutate(ast, context)

      assert [_] = mutations
      assert Enum.any?(mutations, &(&1.ast == nil))
    end

    test "removes and swaps remote function call with two args" do
      ast = {{:., [], [Enum, :map]}, [line: 6], [:list, :func]}
      context = %{file: "test.ex"}

      mutations = FunctionCall.mutate(ast, context)

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(&1.ast == nil))

      assert Enum.any?(
               mutations,
               &(&1.ast == {{:., [], [Enum, :map]}, [line: 6], [:func, :list]})
             )
    end

    test "handles aliased module calls" do
      ast = {{:., [], [{:__aliases__, [], [:MyModule]}, :foo]}, [line: 7], [:a, :b]}
      context = %{file: "test.ex"}

      mutations = FunctionCall.mutate(ast, context)

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(&1.ast == nil))
    end

    test "swaps arguments in remote function call with three arguments" do
      ast = {{:., [], [List, :insert_at]}, [line: 8], [:list, :index, :value]}
      context = %{file: "test.ex"}

      mutations = FunctionCall.mutate(ast, context)

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(&1.ast == nil))

      assert Enum.any?(
               mutations,
               &(&1.ast == {{:., [], [List, :insert_at]}, [line: 8], [:index, :list, :value]})
             )
    end
  end

  describe "mutate/2 - metadata" do
    test "includes proper metadata in mutations" do
      ast = {:foo, [line: 10], [:a, :b]}
      context = %{file: "lib/my_module.ex"}

      mutations = FunctionCall.mutate(ast, context)

      assert [mutation1, mutation2] = mutations
      assert mutation1.mutator == Muex.Mutator.FunctionCall
      assert mutation1.description =~ "FunctionCall:"
      assert mutation1.location.file == "lib/my_module.ex"
      assert mutation1.location.line == 10
      assert mutation2.mutator == Muex.Mutator.FunctionCall
    end

    test "produces correct description for remove mutation" do
      ast = {:calculate, [line: 5], [:x, :y]}
      context = %{file: "test.ex"}

      mutations = FunctionCall.mutate(ast, context)

      remove_mutation = Enum.find(mutations, &(&1.ast == nil))
      assert remove_mutation.description == "FunctionCall: remove calculate() call"
    end

    test "produces correct description for swap mutation" do
      ast = {:process, [line: 6], [:first, :second]}
      context = %{file: "test.ex"}

      mutations = FunctionCall.mutate(ast, context)

      swap_mutation = Enum.find(mutations, &(&1.ast != nil))
      assert swap_mutation.description == "FunctionCall: swap arguments in process()"
      assert swap_mutation.ast == {:process, [line: 6], [:second, :first]}
    end
  end

  describe "mutate/2 - edge cases" do
    test "returns empty list for atoms" do
      ast = :atom
      context = %{}

      assert [] = FunctionCall.mutate(ast, context)
    end

    test "returns empty list for numbers" do
      ast = 42
      context = %{}

      assert [] = FunctionCall.mutate(ast, context)
    end

    test "returns empty list for zero-argument calls" do
      # Note: zero-argument function calls in Elixir don't have an args list in AST
      ast = {:foo, [line: 1], nil}
      context = %{}

      assert [] = FunctionCall.mutate(ast, context)
    end

    test "returns empty list for variables" do
      ast = {:x, [], Elixir}
      context = %{}

      assert [] = FunctionCall.mutate(ast, context)
    end

    test "correctly identifies single argument calls for removal only" do
      ast = {:validate, [line: 9], [:data]}
      context = %{file: "test.ex"}

      mutations = FunctionCall.mutate(ast, context)

      assert [_] = mutations
      assert Enum.all?(mutations, &(&1.ast == nil))
    end

    test "correctly handles four or more argument calls" do
      ast = {:complex, [line: 10], [:a, :b, :c, :d]}
      context = %{file: "test.ex"}

      mutations = FunctionCall.mutate(ast, context)

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(&1.ast == nil))
      assert Enum.any?(mutations, &(&1.ast == {:complex, [line: 10], [:b, :a, :c, :d]}))
    end
  end

  describe "name/0" do
    test "returns mutator name" do
      assert "FunctionCall" = FunctionCall.name()
    end
  end

  describe "description/0" do
    test "returns mutator description" do
      desc = FunctionCall.description()
      assert is_binary(desc)
      assert desc =~ "function call"
    end
  end
end
