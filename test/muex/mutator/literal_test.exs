defmodule Muex.Mutator.LiteralTest do
  use ExUnit.Case, async: true

  alias Muex.Mutator.Literal

  describe "mutate/2 - integers" do
    test "mutates positive integer" do
      ast = 5
      context = %{file: "test.ex"}

      mutations = Literal.mutate(ast, context)

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(&1.ast == 6))
      assert Enum.any?(mutations, &(&1.ast == 4))
    end

    test "mutates zero" do
      ast = 0
      context = %{file: "test.ex"}

      mutations = Literal.mutate(ast, context)

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(&1.ast == 1))
      assert Enum.any?(mutations, &(&1.ast == -1))
    end

    test "mutates negative integer" do
      ast = -3
      context = %{file: "test.ex"}

      mutations = Literal.mutate(ast, context)

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(&1.ast == -2))
      assert Enum.any?(mutations, &(&1.ast == -4))
    end
  end

  describe "mutate/2 - floats" do
    test "mutates positive float" do
      ast = 3.5
      context = %{file: "test.ex"}

      mutations = Literal.mutate(ast, context)

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(&1.ast == 4.5))
      assert Enum.any?(mutations, &(&1.ast == 2.5))
    end

    test "mutates negative float" do
      ast = -1.5
      context = %{file: "test.ex"}

      mutations = Literal.mutate(ast, context)

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(&1.ast == -0.5))
      assert Enum.any?(mutations, &(&1.ast == -2.5))
    end
  end

  describe "mutate/2 - strings" do
    test "mutates non-empty string" do
      ast = "hello"
      context = %{file: "test.ex"}

      mutations = Literal.mutate(ast, context)

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(&1.ast == ""))
      assert Enum.any?(mutations, &(&1.ast == "hellox"))
    end

    test "mutates empty string" do
      ast = ""
      context = %{file: "test.ex"}

      mutations = Literal.mutate(ast, context)

      assert [_] = mutations
      assert Enum.any?(mutations, &(&1.ast == "x"))
    end
  end

  describe "mutate/2 - lists" do
    test "mutates empty list" do
      ast = []
      context = %{file: "test.ex"}

      mutations = Literal.mutate(ast, context)

      assert [_] = mutations
      assert Enum.any?(mutations, &(&1.ast == [:mutated]))
    end
  end

  describe "mutate/2 - atoms" do
    test "mutates regular atom" do
      ast = :foo
      context = %{file: "test.ex"}

      mutations = Literal.mutate(ast, context)

      assert [_] = mutations
      assert Enum.any?(mutations, &(&1.ast == :mutated_atom))
    end

    test "does not mutate nil" do
      ast = nil
      context = %{file: "test.ex"}

      mutations = Literal.mutate(ast, context)

      assert [] = mutations
    end

    test "does not mutate :ok" do
      ast = :ok
      context = %{file: "test.ex"}

      mutations = Literal.mutate(ast, context)

      assert [] = mutations
    end

    test "does not mutate :error" do
      ast = :error
      context = %{file: "test.ex"}

      mutations = Literal.mutate(ast, context)

      assert [] = mutations
    end

    test "does not mutate true (handled by boolean mutator)" do
      ast = true
      context = %{file: "test.ex"}

      mutations = Literal.mutate(ast, context)

      assert [] = mutations
    end

    test "does not mutate false (handled by boolean mutator)" do
      ast = false
      context = %{file: "test.ex"}

      mutations = Literal.mutate(ast, context)

      assert [] = mutations
    end
  end

  describe "mutate/2 - mutation descriptions" do
    test "produces correct descriptions for number mutations" do
      ast = 10
      context = %{file: "test.ex"}

      mutations = Literal.mutate(ast, context)

      assert [mutation1, mutation2] = mutations
      assert mutation1.description == "Literal: 10 to 11 (increment)"
      assert mutation1.ast == 11
      assert mutation2.description == "Literal: 10 to 9 (decrement)"
      assert mutation2.ast == 9
    end

    test "produces correct descriptions for string mutations" do
      ast = "test"
      context = %{file: "test.ex"}

      mutations = Literal.mutate(ast, context)

      assert [mutation1, mutation2] = mutations
      assert mutation1.description == "Literal: \"test\" to \"\" (empty string)"
      assert mutation1.ast == ""
      assert mutation2.description == "Literal: \"test\" to \"testx\" (append char)"
      assert mutation2.ast == "testx"
    end

    test "produces correct description for empty list mutation" do
      ast = []
      context = %{file: "test.ex"}

      [mutation] = Literal.mutate(ast, context)

      assert mutation.description == "Literal: [] to [:mutated]"
      assert mutation.ast == [:mutated]
    end

    test "produces correct description for atom mutation" do
      ast = :custom
      context = %{file: "test.ex"}

      [mutation] = Literal.mutate(ast, context)

      assert mutation.description == "Literal: :custom to :mutated_atom"
      assert mutation.ast == :mutated_atom
    end
  end

  describe "mutate/2 - edge cases" do
    test "includes proper metadata in mutations" do
      ast = 42
      context = %{file: "lib/my_module.ex"}

      mutations = Literal.mutate(ast, context)

      assert [mutation1, mutation2] = mutations
      assert mutation1.mutator == Muex.Mutator.Literal
      assert mutation1.description =~ "Literal:"
      assert mutation1.location.file == "lib/my_module.ex"
      assert mutation2.mutator == Muex.Mutator.Literal
    end

    test "returns empty list for tuples" do
      ast = {:tuple, 1, 2}
      context = %{}

      assert [] = Literal.mutate(ast, context)
    end

    test "returns empty list for complex expressions" do
      ast = {:+, [], [1, 2]}
      context = %{}

      assert [] = Literal.mutate(ast, context)
    end
  end

  describe "mutate/2 - alias atoms" do
    test "does not mutate atoms that look like module aliases" do
      context = %{file: "test.ex"}

      assert [] = Literal.mutate(:Phoenix, context)
      assert [] = Literal.mutate(:Component, context)
      assert [] = Literal.mutate(:MyApp, context)
    end

    test "still mutates lowercase atoms" do
      assert [mutation] = Literal.mutate(:foo, %{file: "test.ex"})
      assert mutation.ast == :mutated_atom
    end
  end

  describe "mutate/2 - context line" do
    test "uses the enclosing line from context when present" do
      assert [m1, m2] = Literal.mutate(5, %{file: "test.ex", line: 12})
      assert m1.location.line == 12
      assert m2.location.line == 12
    end

    test "defaults the line to 0 when context has none" do
      assert [mutation | _] = Literal.mutate(5, %{file: "test.ex"})
      assert mutation.location.line == 0
    end

    test "applies the context line to atom mutations" do
      assert [mutation] = Literal.mutate(:foo, %{file: "test.ex", line: 7})
      assert mutation.location.line == 7
    end
  end

  describe "name/0" do
    test "returns mutator name" do
      assert "Literal" = Literal.name()
    end
  end

  describe "description/0" do
    test "returns mutator description" do
      desc = Literal.description()
      assert is_binary(desc)
      assert desc =~ "literal"
    end
  end
end
