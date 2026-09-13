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
      assert Enum.any?(mutations, &(&1.ast == 0))
    end

    test "mutates multiplication operator" do
      ast = {:*, [line: 3], [:m, :n]}
      context = %{file: "test.ex"}

      mutations = Arithmetic.mutate(ast, context)

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:/, [line: 3], [:m, :n]}))
      assert Enum.any?(mutations, &(&1.ast == 1))
    end

    test "mutates division operator" do
      ast = {:/, [line: 4], [:p, :q]}
      context = %{file: "test.ex"}

      mutations = Arithmetic.mutate(ast, context)

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:*, [line: 4], [:p, :q]}))
      assert Enum.any?(mutations, &(&1.ast == 1))
    end

    test "produces correct mutation descriptions" do
      ast = {:+, [line: 5], [:a, :b]}
      context = %{file: "test.ex"}

      mutations = Arithmetic.mutate(ast, context)

      assert [mutation1, mutation2] = mutations
      assert mutation1.description == "Arithmetic: + to -"
      assert mutation2.description == "Arithmetic: + to 0 (remove)"
    end

    test "includes proper metadata in mutations" do
      ast = {:*, [line: 10], [:x, :y]}
      context = %{file: "lib/calculator.ex"}

      mutations = Arithmetic.mutate(ast, context)

      assert [mutation1, mutation2] = mutations
      assert mutation1.mutator == Muex.Mutator.Arithmetic
      assert mutation1.location.file == "lib/calculator.ex"
      assert mutation1.location.line == 10
      assert mutation2.mutator == Muex.Mutator.Arithmetic
      assert mutation2.location.line == 10
    end

    test "returns empty list for non-arithmetic operators" do
      ast = {:foo, [], []}
      context = %{}

      assert [] = Arithmetic.mutate(ast, context)
    end
  end

  describe "function captures, walked with Muex.Mutator.walk/3" do
    # In `&Path.dirname/1` the `/` names the arity; it is not division. Every
    # mutation of it is an invalid capture: `&(Path.dirname() * 1)` and `&1`
    # do not compile, and for arity 1 the first used to be called equivalent.
    defp walk(source) do
      source
      |> Code.string_to_quoted!()
      |> Muex.Mutator.walk([Arithmetic], %{file: "s.ex"})
    end

    test "the arity of a remote capture is not mutated" do
      assert [] = walk("def a(xs), do: Enum.map(xs, &Path.dirname/1)")
      assert [] = walk("def b(xs), do: Enum.reduce(xs, 0, &Kernel.+/2)")
    end

    test "the arity of a local capture is not mutated" do
      assert [] = walk("def d(xs), do: Enum.map(xs, &double/1)")
    end

    test "division inside a capture is still mutated" do
      # `&(&1 / 2)` also has an integer right of the `/`, directly under `&`.
      # What makes it division is the left operand, `&1`, not a function name.
      mutations = walk("def c(xs), do: Enum.map(xs, &(&1 / 2))")

      assert Enum.map(mutations, & &1.description) == [
               "Arithmetic: / to *",
               "Arithmetic: / to 1 (identity)"
             ]

      assert Enum.all?(mutations, &match?({:/, _meta, [{:&, _, [1]}, 2]}, &1.original_ast))
    end

    test "division by the argument inside a capture is still mutated" do
      # `&(x / &1)` has a variable left of the `/`, like `&fun/1`; what makes it
      # division is that the right is not an integer arity.
      assert [
               %{description: "Arithmetic: / to *"},
               %{description: "Arithmetic: / to 1 (identity)"}
             ] =
               walk("def e(xs, x), do: Enum.map(xs, &(x / &1))")
    end
  end

  describe "name/0" do
    test "returns mutator name" do
      assert "Arithmetic" = Arithmetic.name()
    end
  end
end
