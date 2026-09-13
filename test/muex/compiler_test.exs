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

  describe "apply via compile_to_source/3 - equal nodes on one line" do
    # A mutation used to replace every node on its line that was structurally
    # equal to the one it was generated from. In `x + 1 + (x + 1)` both inner
    # `+ to -` mutants rewrote both copies: two identical mutants, and a report
    # saying one `x + 1` became `x - 1` when both had.
    setup do
      entry = file_entry("defmodule Sample do\n  def f(x), do: x + 1 + (x + 1)\nend")
      %{entry: entry}
    end

    defp body(mutation, entry) do
      assert {:ok, source} = Compiler.compile_to_source(mutation, entry, ElixirLang)
      source |> String.split("\n") |> Enum.at(2) |> String.trim()
    end

    test "mutating the left x + 1 leaves the right one unchanged", %{entry: entry} do
      # walk/3 is pre-order: the outer `+`, then the left `x + 1`, then the right.
      assert [_outer, left, _right] =
               entry.ast
               |> Mutator.walk([Arithmetic], %{file: entry.path})
               |> Enum.filter(&(&1.description == "Arithmetic: + to -"))

      assert body(left, entry) == "x - 1 + (x + 1)"
    end

    test "each + to - mutant rewrites exactly one +", %{entry: entry} do
      bodies =
        entry.ast
        |> Mutator.walk([Arithmetic], %{file: entry.path})
        |> Enum.filter(&(&1.description == "Arithmetic: + to -"))
        |> Enum.map(&body(&1, entry))

      # In walk order: the outer `+`, the left `x + 1`, the right `x + 1`.
      assert bodies == ["x + 1 - (x + 1)", "x - 1 + (x + 1)", "x + 1 + (x - 1)"]
    end

    test "every mutant of the line is distinct", %{entry: entry} do
      bodies =
        entry.ast
        |> Mutator.walk([Arithmetic], %{file: entry.path})
        |> Enum.map(&body(&1, entry))

      assert length(bodies) == 6
      assert bodies == Enum.uniq(bodies)
    end

    test "the first element of a tuple is replaced alone" do
      # `{x + 1, x + 1}` is a two-element tuple: the left `x + 1` is at index 0
      # of a tuple, where the line match would rewrite both.
      entry = file_entry("defmodule Sample do\n  def pair(x), do: {x + 1, x + 1}\nend")

      assert [left, _right] =
               entry.ast
               |> Mutator.walk([Arithmetic], %{file: entry.path})
               |> Enum.filter(&(&1.description == "Arithmetic: + to -"))

      assert body(left, entry) == "{x - 1, x + 1}"
    end

    test "a bare literal is replaced at its own position", %{entry: entry} do
      # Literals carry no metadata, so nothing but their position tells the
      # two `1`s apart.
      bodies =
        entry.ast
        |> Mutator.walk([Literal], %{file: entry.path})
        |> Enum.filter(&(&1.original_ast == 1 and &1.ast == 2))
        |> Enum.map(&body(&1, entry))

      assert bodies == ["x + 2 + (x + 1)", "x + 1 + (x + 2)"]
    end

    test "a mutation built by hand, with no recorded position, still applies by line" do
      entry = file_entry("defmodule Sample do\n  def f(x), do: x * 3\nend")

      mutation = %{
        original_ast: {:*, [line: 2], [{:x, [line: 2], nil}, 3]},
        ast: {:/, [line: 2], [{:x, [line: 2], nil}, 3]},
        mutator: Arithmetic,
        description: "Arithmetic: * to /",
        location: %{file: entry.path, line: 2}
      }

      assert body(mutation, entry) == "x / 3"
    end

    test "a position that does not lead to the node falls back to the line" do
      # Generated from one AST and applied to another. In the second, the
      # recorded position holds `y(x * 3)`, not `x * 3`, and a second
      # definition means it leads nowhere at all. Neither is trusted: the node
      # is found by its line as before.
      generated_from = file_entry("defmodule Sample do\n  def f(x), do: x * 3\nend")

      mutation =
        generated_from.ast
        |> Mutator.walk([Arithmetic], %{file: generated_from.path})
        |> Enum.find(&(&1.description == "Arithmetic: * to /"))

      wrapped = file_entry("defmodule Sample do\n  def f(x), do: y(x * 3)\nend")
      assert body(mutation, wrapped) == "y(x / 3)"

      moved = file_entry("defmodule Sample do\n  def f(x), do: x * 3\n  def g, do: :ok\nend")
      assert body(mutation, moved) == "x / 3"
    end

    test "a position past the end of a tuple or a list falls back to the line" do
      # `g(x * 3)` puts `x * 3` at index 2 of the body's call and index 0 of
      # its args. With `{x * 3, 1}` as the body, the same position is index 2
      # of a two-element tuple; with `g()`, index 0 of an empty list.
      generated_from = file_entry("defmodule Sample do\n  def f(x), do: g(x * 3)\nend")

      mutation =
        generated_from.ast
        |> Mutator.walk([Arithmetic], %{file: generated_from.path})
        |> Enum.find(&(&1.description == "Arithmetic: * to /"))

      pair = file_entry("defmodule Sample do\n  def f(x), do: {x * 3, 1}\nend")
      assert body(mutation, pair) == "{x / 3, 1}"

      empty = file_entry("defmodule Sample do\n  def f(x) when x * 3 > 0, do: g()\nend")
      assert {:ok, source} = Compiler.compile_to_source(mutation, empty, ElixirLang)
      assert source =~ "when x / 3 > 0"
    end

    test "a negative index in a tuple falls back to the line" do
      # `elem/2` refuses a negative index, so the position used to raise.
      entry = file_entry("defmodule Sample do\n  def f(x), do: g(x * 3)\nend")

      mutation =
        entry.ast
        |> Mutator.walk([Arithmetic], %{file: entry.path})
        |> Enum.find(&(&1.description == "Arithmetic: * to /"))
        # The step into the call's args (index 2 of its tuple), made negative.
        |> Map.update!(:ast_path, &List.replace_at(&1, -2, -1))

      assert body(mutation, entry) == "g(x / 3)"
    end

    test "a non-integer index in a tuple falls back to the line" do
      # `walk/3` records integers only, but a position built by hand may not:
      # `elem/2` refuses `2.0`, so it must not be tried.
      entry = file_entry("defmodule Sample do\n  def f(x), do: g(x * 3)\nend")

      mutation =
        entry.ast
        |> Mutator.walk([Arithmetic], %{file: entry.path})
        |> Enum.find(&(&1.description == "Arithmetic: * to /"))
        |> Map.update!(:ast_path, &List.replace_at(&1, -2, 2.0))

      assert body(mutation, entry) == "g(x / 3)"
    end

    test "a negative index in a list falls back to the line" do
      # `Enum.fetch/2` counts a negative index from the end, so the position
      # used to lead to the last `x * 3` and rewrite only that one.
      entry = file_entry("defmodule Sample do\n  def f(x), do: g(x * 3, x * 3)\nend")

      mutation =
        entry.ast
        |> Mutator.walk([Arithmetic], %{file: entry.path})
        |> Enum.find(&(&1.description == "Arithmetic: * to /"))
        # The step to the first argument (index 0 of the args), made negative.
        |> Map.update!(:ast_path, &List.replace_at(&1, -1, -1))

      assert body(mutation, entry) == "g(x / 3, x / 3)"
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

  describe "apply via compile_to_source/3 - map updates" do
    # `%{subject | key: value}` puts a `|` node inside `%{}`, and `%{}` accepts
    # it in exactly one shape. FunctionCall used to treat that `|` as a call and
    # swap its arguments, producing `%{[key: value] | subject}` — an AST no
    # parser produces. Unparsing it raised FunctionClauseError out of
    # `Code.Normalizer.normalize_kw_args/3`, so the mutation could not even be
    # written to the sandbox.
    test "every mutation of a map update unparses" do
      entry =
        file_entry("""
        defmodule Sample do
          def bump(state), do: %{state | count: state.count + 1}
        end
        """)

      mutations = Mutator.walk(entry.ast, [FunctionCall], %{file: entry.path})

      for mutation <- mutations do
        assert {:ok, _source} = Compiler.compile_to_source(mutation, entry, ElixirLang),
               "#{mutation.description} failed to unparse"
      end
    end

    test "every mutation of a struct update unparses" do
      entry =
        file_entry("""
        defmodule Sample do
          def bump(state), do: %Sample.State{state | count: 1}
        end
        """)

      mutations = Mutator.walk(entry.ast, [FunctionCall], %{file: entry.path})

      for mutation <- mutations do
        assert {:ok, _source} = Compiler.compile_to_source(mutation, entry, ElixirLang),
               "#{mutation.description} failed to unparse"
      end
    end

    test "a list cons is still swapped, and the result unparses" do
      entry =
        file_entry("""
        defmodule Sample do
          def prepend(head, tail), do: [head | tail]
        end
        """)

      {:ok, baseline} = ElixirLang.unparse(entry.ast)

      mutation =
        entry.ast
        |> Mutator.walk([FunctionCall], %{file: entry.path})
        |> Enum.find(&String.contains?(&1.description, "swap arguments in |()"))

      assert mutation, "the list cons swap must survive"
      assert {:ok, source} = Compiler.compile_to_source(mutation, entry, ElixirLang)
      assert source != baseline
      assert source =~ "[tail | head]"
    end
  end
end
