defmodule Muex.EquivalenceTest do
  use ExUnit.Case, async: true

  alias Muex.Equivalence

  defp mutation(original, mutated) do
    %{original_ast: original, ast: mutated, mutator: Muex.Mutator.Arithmetic, description: "d"}
  end

  defp quoted(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    ast
  end

  describe "equivalent?/1 — arithmetic identities (sound)" do
    test "a + 0 <-> a - 0 is equivalent (both equal a)" do
      assert Equivalence.equivalent?(mutation(quoted("a + 0"), quoted("a - 0")))
      assert Equivalence.equivalent?(mutation(quoted("a - 0"), quoted("a + 0")))
    end

    test "a * 1 <-> a / 1 is equivalent (both equal a)" do
      assert Equivalence.equivalent?(mutation(quoted("a * 1"), quoted("a / 1")))
      assert Equivalence.equivalent?(mutation(quoted("a / 1"), quoted("a * 1")))
    end

    test "the identity operand must be on the right (0 - a is not equivalent to 0 + a)" do
      refute Equivalence.equivalent?(mutation(quoted("0 + a"), quoted("0 - a")))
      refute Equivalence.equivalent?(mutation(quoted("1 * a"), quoted("1 / a")))
    end

    test "non-identity operands are not equivalent" do
      refute Equivalence.equivalent?(mutation(quoted("a + b"), quoted("a - b")))
      refute Equivalence.equivalent?(mutation(quoted("a + 1"), quoted("a - 1")))
      refute Equivalence.equivalent?(mutation(quoted("a * 2"), quoted("a / 2")))
    end

    test "the + to 0 replacement is NOT treated as equivalent" do
      # Arithmetic also mutates `a + 0` to the literal `0`, which only equals
      # `a + 0` when a == 0 — so it must remain killable.
      refute Equivalence.equivalent?(mutation(quoted("a + 0"), quoted("0")))
    end
  end

  describe "equivalent?/1 — ExtendedMath shift-by-zero (sound)" do
    test "x <<< 0 <-> x >>> 0 is equivalent (both equal x)" do
      assert Equivalence.equivalent?(mutation(quoted("x <<< 0"), quoted("x >>> 0")))
      assert Equivalence.equivalent?(mutation(quoted("x >>> 0"), quoted("x <<< 0")))
    end

    test "a non-zero shift is not equivalent" do
      refute Equivalence.equivalent?(mutation(quoted("x <<< 1"), quoted("x >>> 1")))
    end
  end

  describe "equivalent?/1 — delegation and safety" do
    test "honours a mutation explicitly flagged :equivalent" do
      assert Equivalence.equivalent?(%{ast: :a, original_ast: :b, equivalent: true})
    end

    test "is false for an ordinary, non-equivalent mutation" do
      refute Equivalence.equivalent?(mutation(quoted("a > b"), quoted("a < b")))
    end

    test "is false when original_ast is absent" do
      refute Equivalence.equivalent?(%{ast: quoted("a - 0")})
    end
  end

  describe "filter_equivalent/1" do
    test "drops equivalent mutations and keeps the rest" do
      keep = mutation(quoted("a > b"), quoted("a < b"))
      drop = mutation(quoted("a + 0"), quoted("a - 0"))

      assert Equivalence.filter_equivalent([keep, drop]) == [keep]
    end
  end
end
