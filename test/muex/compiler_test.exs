defmodule Muex.CompilerTest do
  use ExUnit.Case, async: true

  alias Muex.Compiler
  alias Muex.Language.Elixir, as: ElixirLang
  alias Muex.Mutator
  alias Muex.Mutator.Arithmetic
  alias Muex.Mutator.Boolean
  alias Muex.Mutator.FunctionCall
  alias Muex.Mutator.Literal
  alias Muex.Mutator.StatementDeletion

  defp file_entry(source) do
    %{ast: Code.string_to_quoted!(source), path: "sample.ex"}
  end

  describe "apply via compile_to_source/3 - literals" do
    test "replaces a bare literal at its enclosing line" do
      entry =
        file_entry("""
        defmodule Sample do
          def run do
            x = 41
            x + 1
          end
        end
        """)

      mutations = Mutator.walk(entry.ast, [Literal], %{file: entry.path})
      mutation = Enum.find(mutations, &(&1.original_ast == 41 and &1.ast == 42))

      assert {:ok, source} = Compiler.compile_to_source(mutation, entry, ElixirLang)
      assert source =~ "x = 42"
      refute source =~ "x = 41"
      # The unrelated literal on another line is untouched.
      assert source =~ "x + 1"
    end

    test "only replaces the literal on the targeted line, not identical ones elsewhere" do
      entry =
        file_entry("""
        defmodule Sample do
          def a, do: 7
          def b, do: 7
        end
        """)

      mutations = Mutator.walk(entry.ast, [Literal], %{file: entry.path})
      mutation = Enum.find(mutations, &(&1.location.line == 2 and &1.ast == 8))

      assert {:ok, source} = Compiler.compile_to_source(mutation, entry, ElixirLang)
      # def a (line 2) becomes 8; def b (line 3) keeps 7. Match across the
      # block form that Macro.to_string/1 produces.
      assert source =~ ~r/def a do\s+8\s+end/
      assert source =~ ~r/def b do\s+7\s+end/
    end
  end

  describe "apply via compile_to_source/3 - operators and calls" do
    test "applies an arithmetic operator mutation" do
      entry = file_entry("defmodule S do\n  def add(a, b), do: a + b\nend")

      mutations = Mutator.walk(entry.ast, [Arithmetic], %{file: entry.path})
      mutation = Enum.find(mutations, &match?({:-, _meta, _args}, &1.ast))

      assert {:ok, source} = Compiler.compile_to_source(mutation, entry, ElixirLang)
      assert source =~ "a - b"
    end

    test "applies a remote-call argument swap" do
      entry = file_entry("defmodule S do\n  def run(m, k, v), do: Map.put(m, k, v)\nend")

      mutations = Mutator.walk(entry.ast, [FunctionCall], %{file: entry.path})

      mutation =
        Enum.find(mutations, fn m ->
          is_tuple(m.ast) and String.contains?(m.description, "swap") and
            String.contains?(m.description, "put")
        end)

      assert {:ok, source} = Compiler.compile_to_source(mutation, entry, ElixirLang)
      assert source =~ "Map.put(k, m, v)"
    end
  end

  describe "apply via compile_to_source/3 - statement deletion" do
    # StatementDeletion replaces the enclosing `__block__` but reports the
    # deleted statement's line, so the reported line and the line identifying
    # the replaced node are different values. Matching on the reported one made
    # every one of these mutations a no-op: the "mutant" compiled from the
    # untouched original, and the run scored whatever the original scored.
    #
    # Asserting on classification would not catch that — an unmutated mutant
    # still classifies. These tests assert on the source itself.
    setup do
      entry =
        file_entry("""
        defmodule Sample do
          def run(a, b) do
            x = a + b
            y = x * 2
            y - 1
          end
        end
        """)

      {:ok, baseline} = ElixirLang.unparse(entry.ast)
      mutations = Mutator.walk(entry.ast, [StatementDeletion], %{file: entry.path})

      %{entry: entry, baseline: baseline, mutations: mutations}
    end

    test "removes the targeted statement", %{entry: entry, mutations: mutations} do
      mutation = Enum.find(mutations, &(&1.location.line == 3))

      assert {:ok, source} = Compiler.compile_to_source(mutation, entry, ElixirLang)
      refute source =~ "x = a + b"
      assert source =~ "y = x * 2"
      assert source =~ "y - 1"
    end

    test "every deletion actually changes the source", %{
      entry: entry,
      baseline: baseline,
      mutations: mutations
    } do
      assert length(mutations) == 2

      for mutation <- mutations do
        assert {:ok, source} = Compiler.compile_to_source(mutation, entry, ElixirLang)

        assert source != baseline,
               "#{mutation.description} produced the original source unchanged"
      end
    end

    test "reports the deleted statement's line, not the block's", %{mutations: mutations} do
      # The reported line is a display value and must keep pointing at the
      # statement a reader should look at. Application matches on
      # `:original_line` instead, so the two must not be collapsed back
      # into one.
      assert mutations |> Enum.map(& &1.location.line) |> Enum.sort() == [3, 4]
      assert Enum.all?(mutations, &match?({:__block__, _meta, _stmts}, &1.original_ast))
      assert Enum.all?(mutations, &(&1.original_line == 2))
    end
  end

  describe "apply via compile_to_source/3 - bare boolean literals" do
    # The same defect reached by a different route: a bare `true` carries no
    # metadata of its own, so its reported line is inherited from the enclosing
    # node. Matching on the reported line made these mutations no-ops as well.
    test "flips a bare boolean whose reported line points at no node" do
      entry =
        file_entry("""
        defmodule Sample do
          def enabled? do
            true
          end
        end
        """)

      {:ok, baseline} = ElixirLang.unparse(entry.ast)

      assert [mutation] = Mutator.walk(entry.ast, [Boolean], %{file: entry.path})
      assert mutation.original_line == 2

      assert {:ok, source} = Compiler.compile_to_source(mutation, entry, ElixirLang)
      assert source != baseline
      assert source =~ "false"
    end
  end
end
