defmodule Muex.MutantOptimizerTest do
  use ExUnit.Case, async: true

  alias Muex.MutantOptimizer
  alias Muex.Mutator
  alias Muex.Mutator.Comparison

  # The `>` to `<` mutant of the one `a > b` in `source`.
  defp greater_to_less(source) do
    source
    |> Code.string_to_quoted!()
    |> Mutator.walk([Comparison], %{file: "s.ex"})
    |> Enum.filter(&match?({:<, _, _}, &1.ast))
  end

  describe "filter_by_complexity/2" do
    test "keeps a plain swap inside a function that branches" do
      mutations =
        greater_to_less("""
        defmodule S do
          def max(a, b) do
            if a > b, do: a, else: b
          end
        end
        """)

      assert [_] = mutations
      assert [_] = MutantOptimizer.filter_by_complexity(mutations, 2)
    end

    test "drops the same swap inside a one-line function that does not branch" do
      mutations =
        greater_to_less("""
        defmodule S do
          def bigger?(a, b), do: a > b
        end
        """)

      assert [_] = mutations
      assert [] = MutantOptimizer.filter_by_complexity(mutations, 2)
    end

    test "measures each function on its own, not its neighbours" do
      mutations =
        greater_to_less("""
        defmodule S do
          def bigger?(a, b), do: a > b

          def pick(a, b, c) do
            cond do
              a and b -> a
              c -> b
              true -> c
            end
          end
        end
        """)

      assert [_] = mutations
      assert [] = MutantOptimizer.filter_by_complexity(mutations, 2)
    end

    test "a mutation built without a function is measured by its own node, as before" do
      branching = %{ast: quote(do: if(a, do: b, else: c)), mutator: Comparison}
      plain = %{ast: quote(do: a < b), mutator: Comparison}

      assert [^branching] = MutantOptimizer.filter_by_complexity([branching, plain], 2)
    end

    test "a statement deleted outside any function is measured as before, not by the functions after it" do
      mutations =
        """
        defmodule S do
          alias Foo.Bar

          def max(a, b) do
            if a > b, do: a, else: b
          end
        end
        """
        |> Code.string_to_quoted!()
        |> Mutator.walk([Muex.Mutator.StatementDeletion], %{file: "s.ex"})
        |> Enum.reject(&Map.has_key?(&1, :function_complexity))

      assert [_ | _] = mutations
      assert [] = MutantOptimizer.filter_by_complexity(mutations, 2)
    end
  end

  describe "optimize/2 with the balanced preset" do
    test "keeps Comparison and Arithmetic mutants in examples/cart" do
      mutations =
        "examples/cart/lib/**/*.ex"
        |> Path.wildcard()
        |> Enum.flat_map(fn path ->
          path
          |> File.read!()
          |> Code.string_to_quoted!()
          |> Mutator.walk(Muex.Config.all_mutators(), %{file: path})
        end)
        |> Enum.reject(&Muex.Equivalence.equivalent?/1)

      {:ok, config} = Muex.Config.from_args(["--optimize-level", "balanced"])

      kept =
        mutations
        |> MutantOptimizer.optimize(Muex.Config.optimizer_opts(config))
        |> Enum.map(&(&1.mutator |> Module.split() |> List.last()))

      assert "Comparison" in kept
      assert "Arithmetic" in kept
    end
  end
end
