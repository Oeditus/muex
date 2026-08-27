defmodule Muex.Mutator.WalkTest do
  use ExUnit.Case, async: true

  alias Muex.Mutator
  alias Muex.Mutator.Arithmetic
  alias Muex.Mutator.FunctionCall
  alias Muex.Mutator.Literal

  # A minimal mutator that records the enclosing line supplied by the
  # traversal in `context[:line]`. Used to assert line propagation
  # independently of any particular built-in mutator.
  defmodule LineProbe do
    @moduledoc false
    @behaviour Muex.Mutator

    @impl true
    def mutate(node, context) when is_integer(node) do
      [
        %{
          ast: node,
          mutator: __MODULE__,
          description: "probe #{node}",
          location: %{file: Map.get(context, :file, "?"), line: Map.get(context, :line, 0)}
        }
      ]
    end

    def mutate(_node, _context), do: []

    @impl true
    def name, do: "LineProbe"

    @impl true
    def description, do: "probe"

    @impl true
    def supported_languages, do: [Muex.Language.Elixir, Muex.Language.Erlang]
  end

  defp ast!(source), do: Code.string_to_quoted!(source)

  describe "line propagation" do
    test "leaf literals inherit the nearest enclosing line" do
      ast =
        ast!("""
        defmodule Sample do
          def run(x) do
            y = x + 41
            y - 1
          end
        end
        """)

      mutations = Mutator.walk(ast, [LineProbe], %{file: "sample.ex"})
      lines = mutations |> Enum.map(& &1.location.line) |> Enum.sort()

      # 41 is on line 3, 1 is on line 4 of the source above.
      assert 3 in lines
      assert 4 in lines
      refute 0 in lines
    end

    test "defaults the line to 0 when no enclosing metadata exists" do
      # A bare literal has no metadata and no enclosing node.
      assert [mutation] = Mutator.walk(7, [LineProbe], %{file: "bare.ex"})
      assert mutation.location.line == 0
    end
  end

  describe "structural pruning" do
    test "module alias segments are never mutated" do
      ast =
        ast!("""
        defmodule Sample do
          def run, do: Enum.count([1, 2])
        end
        """)

      mutations = Mutator.walk(ast, [Literal], %{file: "s.ex"})

      refute Enum.any?(mutations, &(&1.original_ast in [:Sample, :Enum]))
    end

    test "use/import/alias/require subtrees are skipped" do
      ast =
        ast!("""
        defmodule Sample do
          use GenServer
          import List
          alias Map, as: M
          require Logger
          def run, do: :ok
        end
        """)

      mutations = Mutator.walk(ast, [Literal, FunctionCall], %{file: "s.ex"})

      refute Enum.any?(
               mutations,
               &(&1.original_ast in [:GenServer, :List, :Map, :Logger, :as, :M])
             )
    end

    test "documentation attributes are not mutated" do
      ast =
        ast!(~S'''
        defmodule Sample do
          @moduledoc "module documentation"
          @doc "function documentation"
          def run, do: 1
        end
        ''')

      descriptions =
        ast
        |> Mutator.walk([Literal], %{file: "s.ex"})
        |> Enum.map(& &1.description)

      refute Enum.any?(descriptions, &String.contains?(&1, "documentation"))
    end

    test "keyword keys are skipped but their values are mutated" do
      ast =
        ast!("""
        defmodule Sample do
          def run, do: configure(timeout: 5)
        end
        """)

      mutations = Mutator.walk(ast, [Literal], %{file: "s.ex"})

      refute Enum.any?(mutations, &(&1.original_ast == :timeout))
      assert Enum.any?(mutations, &(&1.original_ast == 5))
    end

    test "the `|` of a map update is skipped but its operands are mutated" do
      ast =
        ast!("""
        defmodule Sample do
          def bump(state), do: %{state | count: state.count + 1}
        end
        """)

      mutations = Mutator.walk(ast, [Literal, FunctionCall, Arithmetic], %{file: "s.ex"})

      refute Enum.any?(mutations, &match?({:|, _meta, _args}, &1.original_ast))
      assert Enum.any?(mutations, &match?({:+, _meta, _args}, &1.original_ast))
      assert Enum.any?(mutations, &(&1.original_ast == 1))
    end

    test "the `|` of a struct update is skipped" do
      ast =
        ast!("""
        defmodule Sample do
          def bump(state), do: %Sample.State{state | count: 1}
        end
        """)

      mutations = Mutator.walk(ast, [Literal, FunctionCall], %{file: "s.ex"})

      refute Enum.any?(mutations, &match?({:|, _meta, _args}, &1.original_ast))
      assert Enum.any?(mutations, &(&1.original_ast == 1))
    end

    test "the `|` of a list cons is still mutated" do
      # `[head | tail]` is a different node in a different position: swapping
      # its arguments unparses and compiles, so it stays a real mutation.
      ast =
        ast!("""
        defmodule Sample do
          def prepend(head, tail), do: [head | tail]
        end
        """)

      mutations = Mutator.walk(ast, [FunctionCall], %{file: "s.ex"})

      assert Enum.any?(mutations, &match?({:|, _meta, _args}, &1.original_ast))
    end
  end

  describe "configurable skip_calls" do
    test "prunes configured DSL calls, leaving the rest intact" do
      ast =
        ast!("""
        defmodule Sample do
          attr :class, :string
          def run, do: 7
        end
        """)

      with_skip = Mutator.walk(ast, [Literal], %{file: "s.ex", skip_calls: [:attr]})
      without_skip = Mutator.walk(ast, [Literal], %{file: "s.ex"})

      refute Enum.any?(with_skip, &(&1.original_ast in [:class, :string]))
      assert Enum.any?(without_skip, &(&1.original_ast in [:class, :string]))
      # The unrelated function body literal is still mutated.
      assert Enum.any?(with_skip, &(&1.original_ast == 7))
    end
  end

  describe "original_ast and backwards compatibility" do
    test "every mutation is augmented with the matched original_ast" do
      ast = ast!("def add(a, b), do: a + b")

      mutations = Mutator.walk(ast, [Arithmetic], %{file: "s.ex"})

      assert Enum.all?(mutations, &Map.has_key?(&1, :original_ast))
      assert Enum.any?(mutations, &match?({:+, _meta, _args}, &1.original_ast))
    end

    test "remote call arguments are still traversed" do
      ast = ast!("def run, do: String.duplicate(\"ab\", 3)")

      mutations = Mutator.walk(ast, [Literal], %{file: "s.ex"})

      assert Enum.any?(mutations, &(&1.original_ast == "ab"))
      assert Enum.any?(mutations, &(&1.original_ast == 3))
    end
  end
end
