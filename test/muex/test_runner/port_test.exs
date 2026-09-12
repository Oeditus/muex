defmodule Muex.TestRunner.PortTest do
  use ExUnit.Case, async: false

  alias Muex.TestRunner.Port, as: PortRunner

  describe "run_tests/2" do
    test "returns error for non-existent test files" do
      result = PortRunner.run_tests(["nonexistent_test.exs"], timeout_ms: 10_000)

      assert match?({:ok, %{exit_code: exit_code}} when exit_code != 0, result) or
               match?({:error, _}, result)
    end

    test "handles empty test file list" do
      result = PortRunner.run_tests([], timeout_ms: 10_000)

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "compile error classification" do
    test "syntax error in test file is classified as compile_error" do
      # Create a test file with invalid Elixir syntax — this will always
      # cause a CompileError regardless of test coverage.
      tmp_dir =
        Path.join(System.tmp_dir!(), "muex_port_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      bad_test = Path.join(tmp_dir, "syntax_error_test.exs")

      File.write!(bad_test, """
      defmodule MuexSyntaxErrorTest#{System.unique_integer([:positive])} do
        use ExUnit.Case
        test "this won't compile" do
          # Missing closing paren — guaranteed CompileError
          Enum.map([1, 2, 3], fn x -> x +
        end
      end
      """)

      try do
        result = PortRunner.run_tests([bad_test], timeout_ms: 15_000)
        assert {:error, {:compile_error, output}} = result
        assert is_binary(output)
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "undefined function call in test file is classified as compile_error" do
      tmp_dir =
        Path.join(System.tmp_dir!(), "muex_port_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      bad_test = Path.join(tmp_dir, "undef_fn_test.exs")

      mod_name = "MuexUndefFnTest#{System.unique_integer([:positive])}"

      File.write!(bad_test, """
      defmodule #{mod_name} do
        use ExUnit.Case
        # Calling a function that doesn't exist at compile time
        @value ThisModuleDoesNotExist.compute()
        test "unreachable" do
          assert @value == 42
        end
      end
      """)

      try do
        result = PortRunner.run_tests([bad_test], timeout_ms: 15_000)
        assert {:error, {:compile_error, output}} = result
        assert is_binary(output)
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "valid test file with real failures is NOT classified as compile_error" do
      tmp_dir =
        Path.join(System.tmp_dir!(), "muex_port_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      good_test = Path.join(tmp_dir, "real_failure_test.exs")

      mod_name = "MuexRealFailureTest#{System.unique_integer([:positive])}"

      File.write!(good_test, """
      defmodule #{mod_name} do
        use ExUnit.Case
        test "deliberately failing" do
          assert 1 == 2
        end
      end
      """)

      try do
        result = PortRunner.run_tests([good_test], timeout_ms: 15_000)
        # Should be a test result with failures, NOT a compile error
        assert {:ok, %{failures: failures}} = result
        assert failures >= 1
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "valid test file with passing tests returns zero failures" do
      tmp_dir =
        Path.join(System.tmp_dir!(), "muex_port_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      good_test = Path.join(tmp_dir, "passing_test.exs")

      mod_name = "MuexPassingTest#{System.unique_integer([:positive])}"

      File.write!(good_test, """
      defmodule #{mod_name} do
        use ExUnit.Case
        test "one plus one" do
          assert 1 + 1 == 2
        end
      end
      """)

      try do
        result = PortRunner.run_tests([good_test], timeout_ms: 15_000)
        assert {:ok, %{failures: 0}} = result
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end

  describe "unmeasurable runs" do
    test "a suite that never reports a summary is an error, not a failure count" do
      # `mix test` aborts before ExUnit runs when the test helper is missing.
      # It prints "** (Mix) Cannot run tests because test helper file ... does
      # not exist", which deliberately does NOT match the compile-error pattern
      # (that requires an exception name ending in "Error" or starting with
      # "Missing"). Nothing measured the mutant, so no verdict may be reported.
      tmp_dir =
        Path.join(System.tmp_dir!(), "muex_port_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(Path.join(tmp_dir, "test"))

      app_name = "muex_no_helper_#{System.unique_integer([:positive])}"

      File.write!(Path.join(tmp_dir, "mix.exs"), """
      defmodule MuexNoHelper#{System.unique_integer([:positive])}.MixProject do
        use Mix.Project

        def project do
          [app: :#{app_name}, version: "0.1.0", elixir: "~> 1.14"]
        end

        def application, do: [extra_applications: []]
      end
      """)

      File.write!(Path.join(tmp_dir, "test/no_helper_test.exs"), """
      defmodule MuexNoHelperTest#{System.unique_integer([:positive])} do
        use ExUnit.Case
        test "never runs" do
          assert 1 + 1 == 2
        end
      end
      """)

      try do
        result =
          PortRunner.run_tests(["test/no_helper_test.exs"], cd: tmp_dir, timeout_ms: 30_000)

        assert {:error, {:no_test_summary, output}} = result
        assert is_binary(output)
        refute Regex.match?(~r/^Result: /m, output)
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end

  # The parsing helpers in Muex.TestRunner.Port are private, so the patterns are
  # re-declared here and asserted against literal `mix test` output captured from
  # both formatter generations — the same approach as "compile error regex" below.
  describe "ExUnit summary parsing" do
    @pre_120_summary_pattern ~r/\d+ tests?, \d+ failures?/
    @post_120_summary_pattern ~r/^Result: /m
    @pre_120_failures_pattern ~r/(\d+) failures?/
    @post_120_failures_pattern ~r/^Failed: (\d+) tests?/m

    # Elixir < 1.20
    @pre_120_green "Finished in 0.05 seconds\n5 tests, 0 failures"
    @pre_120_red "Finished in 0.05 seconds\n5 tests, 2 failures"

    # Elixir >= 1.20 (captured from real runs on 1.20.3)
    @post_120_green "Finished in 0.00 seconds\n\nResult: 1 passed"
    @post_120_red "Finished in 0.00 seconds\n\nResult: 0/1 passed, 1 skipped\nFailed: 1 test"
    @post_120_red_plural "Finished in 0.00 seconds\n\nResult: 0/2 passed\nFailed: 2 tests"
    @post_120_mixed "Result: 1/2 passed, 1 skipped, 1 excluded\nFailed: 1 test"
    @post_120_all_excluded "Result: 0 tests, 1 excluded"
    @post_120_invalid "Result: 0 tests, 1 invalid"

    test "recognises the pre-1.20 summary" do
      assert Regex.match?(@pre_120_summary_pattern, @pre_120_green)
      assert Regex.match?(@pre_120_summary_pattern, @pre_120_red)
    end

    test "recognises the 1.20 summary in every observed form" do
      for output <- [
            @post_120_green,
            @post_120_red,
            @post_120_red_plural,
            @post_120_mixed,
            @post_120_all_excluded,
            @post_120_invalid
          ] do
        assert Regex.match?(@post_120_summary_pattern, output),
               "expected a Result: line in #{inspect(output)}"
      end
    end

    test "1.20 output carries no pre-1.20 summary — this is the bug" do
      # 1.20 prints the word "failures" nowhere, so the old parser saw no
      # summary at all and guessed a failure count of 1 for every mutant.
      for output <- [@post_120_green, @post_120_red, @post_120_red_plural] do
        refute Regex.match?(@pre_120_summary_pattern, output)
        refute Regex.match?(@pre_120_failures_pattern, output)
        refute String.contains?(output, "0 failures")
      end
    end

    test "counts failures from the pre-1.20 summary" do
      assert [_, "0"] = Regex.run(@pre_120_failures_pattern, @pre_120_green)
      assert [_, "2"] = Regex.run(@pre_120_failures_pattern, @pre_120_red)
    end

    test "counts failures from the 1.20 Failed: line, singular and plural" do
      assert [_, "1"] = Regex.run(@post_120_failures_pattern, @post_120_red)
      assert [_, "2"] = Regex.run(@post_120_failures_pattern, @post_120_red_plural)
      assert [_, "1"] = Regex.run(@post_120_failures_pattern, @post_120_mixed)
    end

    test "1.20 green and no-test runs carry no Failed: line" do
      refute Regex.match?(@post_120_failures_pattern, @post_120_green)
      refute Regex.match?(@post_120_failures_pattern, @post_120_all_excluded)
      refute Regex.match?(@post_120_failures_pattern, @post_120_invalid)
    end

    test "both summary and failure patterns are line-anchored" do
      refute Regex.match?(@post_120_summary_pattern, "see the Result: line above")
      refute Regex.match?(@post_120_failures_pattern, "nothing Failed: 3 tests here")
    end
  end

  # A mutant whose chosen tests were all excluded, skipped or invalid was never
  # tested. `mix test` still exits 0, so the count of tests that ran is the only
  # thing that tells it apart from a real survivor.
  describe "tests_run/1" do
    test "reads the 1.20 summary: only passed and failed tests ran" do
      assert PortRunner.tests_run("Finished in 0.00 seconds\n\nResult: 1 passed") == 1
      assert PortRunner.tests_run("Result: 0/1 passed, 1 skipped\nFailed: 1 test") == 1
      assert PortRunner.tests_run("Result: 0/2 passed\nFailed: 2 tests") == 2

      assert PortRunner.tests_run("Result: 1/2 passed, 1 skipped, 1 excluded\nFailed: 1 test") ==
               2

      assert PortRunner.tests_run("Result: 455 passed (70 tests, 14 properties)") == 455
    end

    test "reads a 1.20 run where nothing ran as zero" do
      assert PortRunner.tests_run("Result: 0 tests, 1 excluded") == 0
      assert PortRunner.tests_run("Result: 0 tests, 1 invalid") == 0
      assert PortRunner.tests_run("Result: 0 tests, 2 skipped") == 0
    end

    test "reads the pre-1.20 summary, which counts excluded and skipped tests too" do
      assert PortRunner.tests_run("Finished in 0.05 seconds\n5 tests, 0 failures") == 5
      assert PortRunner.tests_run("5 tests, 2 failures") == 5
      assert PortRunner.tests_run("1 doctest, 2 tests, 0 failures, 1 skipped") == 2
      assert PortRunner.tests_run("3 tests, 0 failures, 3 excluded") == 0

      assert PortRunner.tests_run(
               "All tests have been excluded.\n\n3 tests, 0 failures, 3 excluded"
             ) == 0

      assert PortRunner.tests_run("2 tests, 0 failures, 1 excluded, 1 skipped") == 0
      assert PortRunner.tests_run("0 failures") == 0
    end

    test "adds up one summary per app, as an umbrella prints" do
      assert PortRunner.tests_run("==> a\nResult: 0 tests, 2 excluded\n==> b\nResult: 3 passed") ==
               3

      assert PortRunner.tests_run(
               "==> a\nResult: 0 tests, 2 excluded\n==> b\nResult: 0 tests, 1 skipped"
             ) == 0

      assert PortRunner.tests_run(
               "==> a\n2 tests, 0 failures, 2 excluded\n==> b\n1 test, 0 failures"
             ) == 1
    end

    test "is nil when there is no count to read" do
      assert PortRunner.tests_run("** (Mix) Cannot run tests") == nil
      assert PortRunner.tests_run("see the Result: line above") == nil
    end

    test "a real run whose only test is skipped exits 0 and ran nothing" do
      tmp_dir =
        Path.join(System.tmp_dir!(), "muex_port_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      skipped_test = Path.join(tmp_dir, "skipped_test.exs")

      File.write!(skipped_test, """
      defmodule MuexSkippedTest#{System.unique_integer([:positive])} do
        use ExUnit.Case
        @tag :skip
        test "never runs" do
          assert 1 + 1 == 2
        end
      end
      """)

      try do
        assert {:ok, %{failures: 0, tests_run: 0, exit_code: 0}} =
                 PortRunner.run_tests([skipped_test], timeout_ms: 30_000)
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end

  describe "summary_counts/2" do
    test "sums failures over every summary, as an umbrella prints one per app" do
      output = "==> a\n2 tests, 0 failures\n==> b\n1 test, 1 failure"
      assert %{failures: 1, tests_run: 3} = PortRunner.summary_counts(output, 1)

      output = "==> a\nResult: 2 passed\n==> b\nResult: 0/1 passed\nFailed: 1 test"
      assert %{failures: 1, tests_run: 3} = PortRunner.summary_counts(output, 1)
    end

    # A setup_all crash counts its tests invalid, not failed, and exits non-zero.
    # It must read as a failure, not as a pass and not as "nothing ran".
    test "a non-zero exit with no failure counted is a failure" do
      assert %{failures: 1, tests_run: 0} =
               PortRunner.summary_counts("1 test, 0 failures, 1 invalid", 1)

      assert %{failures: 1, tests_run: 0} =
               PortRunner.summary_counts("Result: 0 tests, 1 invalid", 1)
    end

    test "a zero exit with no failure counted is a pass" do
      assert %{failures: 0, tests_run: 0} =
               PortRunner.summary_counts("3 tests, 0 failures, 3 excluded", 0)

      assert %{failures: 0, tests_run: 3} = PortRunner.summary_counts("Result: 3 passed", 0)
    end

    test "reads a summary that forced ExUnit colours wrapped in escape codes" do
      output = "\e[31m2 tests, 1 failure, 1 excluded\e[0m\n"
      assert %{failures: 1, tests_run: 1} = PortRunner.summary_counts(output, 1)

      output = "\e[32m3 tests, 0 failures, 3 excluded\e[0m\n"
      assert %{failures: 0, tests_run: 0} = PortRunner.summary_counts(output, 0)
    end

    test "a real setup_all crash is counted as a failure" do
      tmp_dir =
        Path.join(System.tmp_dir!(), "muex_port_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      crash_test = Path.join(tmp_dir, "setup_all_crash_test.exs")

      File.write!(crash_test, """
      defmodule MuexSetupAllCrashTest#{System.unique_integer([:positive])} do
        use ExUnit.Case
        setup_all do
          raise "setup_all blew up"
        end

        test "never runs" do
          assert 1 + 1 == 2
        end
      end
      """)

      try do
        assert {:ok, %{failures: failures, exit_code: exit_code}} =
                 PortRunner.run_tests([crash_test], timeout_ms: 30_000)

        assert exit_code != 0
        assert failures >= 1
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end

  describe "error_files/1" do
    test "names the file a real failed compile names, and nothing else" do
      for {name, source} <- [
            syntax: "defmodule B do\n  def f(, do: 1\nend\n",
            undefined_function: "defmodule B do\n  def f, do: nope()\nend\n"
          ] do
        with_project(%{"lib/b.ex" => source}, fn root ->
          assert {:error, {:compile_error, output}} =
                   PortRunner.run_tests(["test/a_test.exs"], cd: root, timeout_ms: 60_000)

          assert PortRunner.error_files(output) == [{nil, "lib/b.ex"}], "#{name}: #{output}"
        end)
      end
    end

    # The compiler prints every warning of the files it compiled beside the
    # error, so a warning's file is not the error's cause.
    test "a real warning printed beside an error in another file is not named" do
      files = %{
        "lib/a.ex" => "defmodule A do\n  def two, do: 2\n  def noisy(unused), do: 1\nend\n",
        "lib/b.ex" => "defmodule B do\n  def f, do: nope()\nend\n"
      }

      with_project(files, fn root ->
        assert {:error, {:compile_error, output}} =
                 PortRunner.run_tests(["test/a_test.exs"], cd: root, timeout_ms: 60_000)

        assert output =~ "lib/a.ex"
        assert PortRunner.error_files(output) == [{nil, "lib/b.ex"}]
        assert PortRunner.compile_failed?(output)
      end)
    end

    # After an error's pointer, the stack trace of a module that raised while
    # compiling lists project files with no app in front ("lib/a.ex:3: ..."),
    # which must not be read as more pointers. Captured from Elixir 1.20.2
    # (lib/c.ex calls A.helper/0, which raises, in a module attribute); the
    # parallel compiler prints the two errors in either order, so it is a fixture.
    test "a stack trace after an error is not read as the error's file" do
      output = """
      Compiling 3 files (.ex)
          error: undefined function nope/0 (expected B to define such a function or for it to be imported, but none are available)
          │
        2 │   def f, do: nope()
          │              ^^^^
          │
          └─ lib/b.ex:2:14: B.f/0


      == Compilation error in file lib/c.ex ==
      ** (RuntimeError) boom
          lib/a.ex:3: A.helper/0
          lib/c.ex:2: (module)
      """

      assert PortRunner.error_files(output) == [{nil, "lib/b.ex"}, {nil, "lib/c.ex"}]

      # the same on Elixir 1.15, where the pointer is itself an indented line
      output = """
      error: undefined function nope/0 (expected B to define such a function or for it to be imported, but none are available)
        lib/b.ex:2: B.f/0

      ** (RuntimeError) boom
          lib/a.ex:3: A.helper/0
      """

      assert PortRunner.error_files(output) == [{nil, "lib/b.ex"}]
    end

    test "names a test file that does not compile" do
      with_project(%{"test/a_test.exs" => "defmodule ATest do\n  use ExUnit.Case\n"}, fn root ->
        assert {:error, {:compile_error, output}} =
                 PortRunner.run_tests(["test/a_test.exs"], cd: root, timeout_ms: 60_000)

        assert {nil, "test/a_test.exs"} in PortRunner.error_files(output)
      end)
    end

    # Captured from Elixir 1.20.2 and 1.18.4, which print it alike: an umbrella
    # prints each app's paths relative to that app, under its "==> app" header.
    test "an umbrella's path comes with the app it was compiled in" do
      output = """
      ==> a
      Compiling 1 file (.ex)
      Generated a app
      ==> b
      Compiling 1 file (.ex)

      == Compilation error in file lib/b.ex ==
      ** (MismatchedDelimiterError) mismatched delimiter found on lib/b.ex:3:1:
          error: unexpected reserved word: end
          │
        2 │   def f(, do: 1
          │        └ unclosed delimiter
        3 │ end
          │ └ mismatched closing delimiter (expected ")")
          │
          └─ lib/b.ex:3:1
          (elixir 1.20.2) lib/kernel/parallel_compiler.ex:548: anonymous fn/5 in Kernel.ParallelCompiler.spawn_workers/8
      """

      assert PortRunner.error_files(output) == [{"b", "lib/b.ex"}]
    end

    # A --warnings-as-errors build names the file only under the warning.
    test "a warning that fails the build names its file" do
      output = """
      Compiling 1 file (.ex)
          warning: variable "b" is unused (if the variable is not meant to be used, prefix it with an underscore)
          │
        3 │   def add(a, b), do: a
          │              ~
          │
          └─ lib/a.ex:3:14: A.add/2

      warning: expected an integer in binary size:
      └─ lib/c.ex: C.first/1

      Compilation failed due to warnings while using the --warnings-as-errors option
      """

      assert PortRunner.error_files(output) == [{nil, "lib/a.ex"}, {nil, "lib/c.ex"}]
      assert PortRunner.compile_failed?(output)
    end

    # Elixir 1.15.8's wording: the path comes first on the "**" line, and a
    # diagnostic names its file on an indented line of its own, without "└─".
    # The first and last outputs are as it printed them; the middle one joins
    # its warning and error formats.
    test "reads the Elixir 1.15 wording" do
      output = """
      == Compilation error in file lib/b.ex ==
      ** (SyntaxError) lib/b.ex:3:1: unexpected reserved word: end

          HINT: the "(" on line 2 is missing terminator ")"

          |
        3 | end
          | ^
          (elixir 1.15.8) lib/kernel/parallel_compiler.ex:377: anonymous fn/5 in Kernel.ParallelCompiler.spawn_workers/8
      """

      assert PortRunner.error_files(output) == [{nil, "lib/b.ex"}]

      output = """
      Compiling 2 files (.ex)
      warning: variable "unused" is unused (if the variable is not meant to be used, prefix it with an underscore)
        lib/a.ex:3: A.noisy/1

      error: undefined function nope/0 (expected B to define such a function or for it to be imported, but none are available)
        lib/b.ex:2: B.f/0


      == Compilation error in file lib/b.ex ==
      ** (CompileError) lib/b.ex: cannot compile module B (errors have been logged)
      """

      assert PortRunner.error_files(output) == [{nil, "lib/b.ex"}]

      output = """
      Compiling 2 files (.ex)
      warning: this clause cannot match because '2.0' is not a valid size for a binary segment
        lib/b.ex:3

      Compilation failed due to warnings while using the --warnings-as-errors option
      """

      assert PortRunner.error_files(output) == [{nil, "lib/b.ex"}]
    end

    test "names nothing when no file is named" do
      assert PortRunner.error_files("** (Mix) Could not compile dependency :foo") == []
      refute PortRunner.compile_failed?("** (Mix) Could not compile dependency :foo")
    end
  end

  describe "run_tests/2 with exclude_all" do
    test "compiles and loads the tests, and runs none" do
      with_project(%{}, fn root ->
        assert {:ok, %{failures: 0, tests_run: 0, exit_code: 0}} =
                 PortRunner.run_tests(["test/a_test.exs"],
                   cd: root,
                   timeout_ms: 60_000,
                   exclude_all: true
                 )
      end)
    end
  end

  # A one-module project whose test passes, with `files` written over it.
  defp with_project(files, fun) do
    root = Path.join(System.tmp_dir!(), "muex_port_test_#{System.unique_integer([:positive])}")

    base = %{
      "mix.exs" => """
      defmodule PortTiny.MixProject do
        use Mix.Project
        def project, do: [app: :port_tiny, version: "0.1.0"]
      end
      """,
      "lib/a.ex" => "defmodule A do\n  def two, do: 2\nend\n",
      "test/test_helper.exs" => "ExUnit.start()\n",
      "test/a_test.exs" =>
        "defmodule ATest do\n  use ExUnit.Case\n  test \"two\", do: assert(A.two() == 2)\nend\n"
    }

    for {path, content} <- Map.merge(base, files) do
      File.mkdir_p!(Path.dirname(Path.join(root, path)))
      File.write!(Path.join(root, path), content)
    end

    try do
      fun.(root)
    after
      File.rm_rf!(root)
    end
  end

  describe "compile error regex" do
    @compile_error_pattern ~r/\*\* \([\w.]*(?:Error|Missing[\w.]*)\)/

    test "matches common Elixir compilation exceptions" do
      assert Regex.match?(@compile_error_pattern, "** (CompileError) lib/foo.ex:1")
      assert Regex.match?(@compile_error_pattern, "** (SyntaxError) lib/foo.ex:1")
      assert Regex.match?(@compile_error_pattern, "** (TokenMissingError) lib/foo.ex:1")
      assert Regex.match?(@compile_error_pattern, "** (ArgumentError) bad argument")
      assert Regex.match?(@compile_error_pattern, "** (UndefinedFunctionError) undefined")
      assert Regex.match?(@compile_error_pattern, "** (File.Error) could not read file")
      assert Regex.match?(@compile_error_pattern, "** (Jason.DecodeError) invalid json")
    end

    test "does not match non-error output" do
      refute Regex.match?(@compile_error_pattern, "warning: unused variable")
      refute Regex.match?(@compile_error_pattern, "5 tests, 2 failures")
      refute Regex.match?(@compile_error_pattern, "Compiling 1 file (.ex)")
    end
  end
end
