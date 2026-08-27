defmodule Muex.Mutator.BooleanTest do
  use ExUnit.Case, async: true

  alias Muex.Mutator.Boolean

  describe "mutate/2" do
    test "mutates and operator" do
      ast = {:and, [line: 1], [:a, :b]}
      context = %{file: "test.ex"}

      mutations = Boolean.mutate(ast, context)

      assert [_] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:or, [line: 1], [:a, :b]}))
    end

    test "mutates or operator" do
      ast = {:or, [line: 2], [:x, :y]}
      context = %{file: "test.ex"}

      mutations = Boolean.mutate(ast, context)

      assert [_] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:and, [line: 2], [:x, :y]}))
    end

    test "mutates && operator" do
      ast = {:&&, [line: 3], [:a, :b]}
      context = %{file: "test.ex"}

      mutations = Boolean.mutate(ast, context)

      assert [_] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:||, [line: 3], [:a, :b]}))
    end

    test "mutates || operator" do
      ast = {:||, [line: 4], [:x, :y]}
      context = %{file: "test.ex"}

      mutations = Boolean.mutate(ast, context)

      assert [_] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:&&, [line: 4], [:x, :y]}))
    end

    test "mutates true literal" do
      ast = true
      context = %{file: "test.ex"}

      mutations = Boolean.mutate(ast, context)

      assert [_] = mutations
      assert Enum.any?(mutations, &(&1.ast == false))
    end

    test "mutates false literal" do
      ast = false
      context = %{file: "test.ex"}

      mutations = Boolean.mutate(ast, context)

      assert [_] = mutations
      assert Enum.any?(mutations, &(&1.ast == true))
    end

    test "removes negation operator" do
      ast = {:not, [line: 5], [:x]}
      context = %{file: "test.ex"}

      mutations = Boolean.mutate(ast, context)

      assert [_] = mutations
      assert Enum.any?(mutations, &(&1.ast == :x))
    end

    test "removes negation with complex expression" do
      ast = {:not, [line: 6], [{:>, [], [:a, :b]}]}
      context = %{file: "test.ex"}

      mutations = Boolean.mutate(ast, context)

      assert [_] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:>, [], [:a, :b]}))
    end

    test "produces correct mutation descriptions for operator swaps" do
      test_cases = [
        {:and, :or, "Boolean: and to or"},
        {:or, :and, "Boolean: or to and"},
        {:&&, :||, "Boolean: && to ||"},
        {:||, :&&, "Boolean: || to &&"}
      ]

      for {op, expected_op, expected_desc} <- test_cases do
        ast = {op, [line: 1], [:a, :b]}
        context = %{file: "test.ex"}
        [mutation] = Boolean.mutate(ast, context)
        assert mutation.description == expected_desc
        assert mutation.ast == {expected_op, [line: 1], [:a, :b]}
      end
    end

    test "produces correct mutation descriptions for literal swaps" do
      ast_true = true
      context = %{file: "test.ex"}
      [mutation_true] = Boolean.mutate(ast_true, context)
      assert mutation_true.description == "Boolean: true to false"
      assert mutation_true.ast == false

      ast_false = false
      [mutation_false] = Boolean.mutate(ast_false, context)
      assert mutation_false.description == "Boolean: false to true"
      assert mutation_false.ast == true
    end

    test "produces correct mutation description for negation removal" do
      ast = {:not, [line: 7], [:condition]}
      context = %{file: "test.ex"}

      [mutation] = Boolean.mutate(ast, context)

      assert mutation.description == "Boolean: remove not (not x to x)"
      assert mutation.ast == :condition
    end

    test "includes proper metadata in mutations" do
      ast = {:and, [line: 10], [:a, :b]}
      context = %{file: "lib/my_module.ex"}

      [mutation] = Boolean.mutate(ast, context)

      assert mutation.mutator == Muex.Mutator.Boolean
      assert mutation.description =~ "Boolean:"
      assert mutation.location.file == "lib/my_module.ex"
      assert mutation.location.line == 10
    end

    test "returns empty list for non-boolean operators" do
      ast = {:+, [line: 1], [:a, :b]}
      context = %{}

      assert [] = Boolean.mutate(ast, context)
    end

    test "returns empty list for other atoms" do
      ast = :ok
      context = %{}

      assert [] = Boolean.mutate(ast, context)
    end

    test "returns empty list for numbers" do
      ast = 42
      context = %{}

      assert [] = Boolean.mutate(ast, context)
    end
  end

  describe "mutate/2 - context line" do
    test "uses the enclosing line from context for a bare true" do
      assert [mutation] = Boolean.mutate(true, %{file: "test.ex", line: 12})
      assert mutation.location.line == 12
    end

    test "uses the enclosing line from context for a bare false" do
      assert [mutation] = Boolean.mutate(false, %{file: "test.ex", line: 9})
      assert mutation.location.line == 9
    end

    test "defaults the line to 0 when context has none" do
      assert [mutation] = Boolean.mutate(true, %{file: "test.ex"})
      assert mutation.location.line == 0
    end
  end

  describe "walk/3 integration" do
    test "boolean literals in real source report a line, not 0" do
      ast =
        Code.string_to_quoted!("""
        defmodule Sample do
          def enabled?, do: true

          def disabled?, do: false
        end
        """)

      mutations = Muex.Mutator.walk(ast, [Boolean], %{file: "sample.ex"})
      lines = mutations |> Enum.map(& &1.location.line) |> Enum.sort()

      # `true` is on line 2, `false` on line 4 of the source above.
      assert lines == [2, 4]
      refute 0 in lines
    end
  end

  describe "name/0" do
    test "returns mutator name" do
      assert "Boolean" = Boolean.name()
    end
  end

  describe "description/0" do
    test "returns mutator description" do
      desc = Boolean.description()
      assert is_binary(desc)
      assert desc =~ "boolean"
    end
  end
end
