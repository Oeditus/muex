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
