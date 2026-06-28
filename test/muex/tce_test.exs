defmodule Muex.TceTest.AfterVerifyHook do
  @moduledoc false
  # Stands in for what `use Ash.Resource`/Spark inject: an `@after_verify`
  # callback that emits warnings while a module is verified. Spark's real
  # `__verify_spark_dsl__/1` both warns about domain config and re-emits caught
  # verifier exceptions as warnings; a single `IO.warn` is enough to detect the
  # leak the probe used to cause (issue #17).
  def verify(module) do
    IO.warn("after_verify hook ran for #{inspect(module)}", [])
    :ok
  end
end

defmodule Muex.TceTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Muex.Tce

  defp quoted(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    ast
  end

  describe "equivalent?/2 — provable compiler equivalence" do
    test "deleting a @moduledoc is equivalent (identical function bytecode)" do
      a = quoted(~S|defmodule M do
        @moduledoc "docs"
        def f(x), do: x + 1
      end|)

      b = quoted(~S|defmodule M do
        def f(x), do: x + 1
      end|)

      assert Tce.equivalent?(a, b)
    end

    test "a line-only difference is equivalent" do
      a = quoted("defmodule M do\n  def f, do: 1\nend")
      b = quoted("defmodule M do\n\n\n  def f, do: 1\nend")

      assert Tce.equivalent?(a, b)
    end

    test "deleting a @doc on a function with an unchanged body is equivalent" do
      a = quoted(~S|defmodule M do
        @doc "hi"
        def f(x), do: x * 2
      end|)

      b = quoted(~S|defmodule M do
        def f(x), do: x * 2
      end|)

      assert Tce.equivalent?(a, b)
    end
  end

  describe "equivalent?/2 — genuinely different code is kept" do
    test "a different return value is not equivalent" do
      a = quoted("defmodule M do def f, do: 1 end")
      b = quoted("defmodule M do def f, do: 2 end")

      refute Tce.equivalent?(a, b)
    end

    test "a different operator is not equivalent" do
      a = quoted("defmodule M do def f(x), do: x + 1 end")
      b = quoted("defmodule M do def f(x), do: x - 1 end")

      refute Tce.equivalent?(a, b)
    end
  end

  describe "equivalent_source?/2 — mutated source vs original AST" do
    test "true when the mutated source compiles to identical bytecode" do
      original = quoted(~S|defmodule M do
        @moduledoc "docs"
        def f(x), do: x + 1
      end|)

      mutated_source = ~S|defmodule M do
        def f(x), do: x + 1
      end|

      assert Tce.equivalent_source?(original, mutated_source)
    end

    test "false when the mutated source changes behaviour" do
      original = quoted("defmodule M do def f, do: 1 end")
      assert not Tce.equivalent_source?(original, "defmodule M do def f, do: 2 end")
    end

    test "false when the mutated source does not parse" do
      original = quoted("defmodule M do def f, do: 1 end")
      assert not Tce.equivalent_source?(original, "defmodule M do def f, do: end")
    end
  end

  describe "equivalent?/2 — modules with closures (regression)" do
    # BEAM derives a closure's identity hash from the module name; comparing two
    # compiles under *different* throwaway names made even identical code with a
    # function capture fingerprint differently. Both sides must share one name.
    test "a module containing a function capture is equivalent to itself" do
      m =
        quoted(~S|defmodule M do
          def f(xs), do: Enum.map(xs, &g/1)
          def g(x), do: x + 1
        end|)

      assert Tce.equivalent?(m, m)
    end

    test "deleting a @moduledoc is equivalent even when the module uses a capture" do
      a =
        quoted(~S|defmodule M do
          @moduledoc "docs"
          def f(xs), do: Enum.map(xs, &g/1)
          def g(x), do: x + 1
        end|)

      b =
        quoted(~S|defmodule M do
          def f(xs), do: Enum.map(xs, &g/1)
          def g(x), do: x + 1
        end|)

      assert Tce.equivalent?(a, b)
    end
  end

  describe "equivalent?/2 — module-name changes are observable" do
    test "two modules with identical bodies but different names are NOT equivalent" do
      a = quoted("defmodule Foo do def f, do: 1 end")
      b = quoted("defmodule Bar do def f, do: 1 end")

      # Renaming a module is killable (callers can no longer find it), so even
      # byte-identical function bodies must not be reported equivalent.
      refute Tce.equivalent?(a, b)
    end
  end

  describe "equivalent?/2 — modules with @after_verify hooks (issue #17 regression)" do
    # Renaming a Spark/Ash resource to a throwaway probe name and recompiling it
    # used to fire its `@after_verify` verifier, whose warnings the parallel
    # checker prints unconditionally — escaping `Code.with_diagnostics/2` and
    # flooding the console with one batch per resource module per mutant. TCE now
    # compiles the probe without the verification pass, so nothing is emitted.
    test "probing a module with an @after_verify hook emits nothing to stderr" do
      ast =
        quoted(~S|defmodule M do
          @after_verify {Muex.TceTest.AfterVerifyHook, :verify}
          def f(x), do: x + 1
        end|)

      # A self-comparison compiles the probe twice — both sides must stay silent.
      {result, stderr} = with_io(:stderr, fn -> Tce.equivalent?(ast, ast) end)

      assert result
      assert stderr == ""
    end

    test "still detects equivalence for a module that registers an @after_verify hook" do
      a =
        quoted(~S|defmodule M do
          @moduledoc "docs"
          @after_verify {Muex.TceTest.AfterVerifyHook, :verify}
          def f(x), do: x + 1
        end|)

      b =
        quoted(~S|defmodule M do
          @after_verify {Muex.TceTest.AfterVerifyHook, :verify}
          def f(x), do: x + 1
        end|)

      # Skipping verification must not change the bytecode comparison: deleting a
      # @moduledoc is still provably equivalent, and still no output leaks.
      {result, stderr} = with_io(:stderr, fn -> Tce.equivalent?(a, b) end)

      assert result
      assert stderr == ""
    end
  end

  describe "equivalent?/2 — safety" do
    test "is false (not provably equivalent) when one side fails to compile" do
      a = quoted("defmodule M do def f, do: 1 end")
      b = quoted("defmodule M do def f, do: undefined_var end")

      refute Tce.equivalent?(a, b)
    end

    test "refuses anything that is not a single defmodule (never compiles real modules)" do
      # A bare expression cannot be renamed to a throwaway module, so TCE bails
      # rather than risk compiling/clobbering the project's real modules.
      refute Tce.equivalent?(quoted("1 + 1"), quoted("1 + 1"))
    end
  end
end
