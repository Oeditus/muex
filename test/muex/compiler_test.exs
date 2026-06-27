defmodule Muex.CompilerTest do
  use ExUnit.Case, async: true

  alias Muex.Compiler
  alias Muex.Language.Elixir, as: ElixirLang
  alias Muex.Mutator
  alias Muex.Mutator.Arithmetic
  alias Muex.Mutator.FunctionCall
  alias Muex.Mutator.Literal

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
end
