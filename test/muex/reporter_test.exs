defmodule Muex.ReporterTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Muex.Reporter

  describe "print_summary/1" do
    test "prints basic mutation score" do
      results = [
        %{result: :killed, mutation: test_mutation()},
        %{result: :killed, mutation: test_mutation()},
        %{result: :survived, mutation: test_mutation()}
      ]

      output = capture_io(fn -> Reporter.print_summary(results) end)

      assert output =~ "Total mutants:\e[0m 3"
      assert output =~ "Killed:\e[0m 2"
      assert output =~ "Survived:\e[0m 1"
      assert output =~ "Mutation Score: \e[33m66.67%\e[0m"
    end

    test "handles all killed mutations" do
      results = [
        %{result: :killed, mutation: test_mutation()},
        %{result: :killed, mutation: test_mutation()}
      ]

      output = capture_io(fn -> Reporter.print_summary(results) end)

      assert output =~ "Total mutants:\e[0m 2"
      assert output =~ "Killed:\e[0m 2"
      assert output =~ "Survived:\e[0m 0"
      assert output =~ "Mutation Score: \e[32m100.0%\e[0m"
    end

    test "handles all survived mutations" do
      results = [
        %{result: :survived, mutation: test_mutation()},
        %{result: :survived, mutation: test_mutation()}
      ]

      output = capture_io(fn -> Reporter.print_summary(results) end)

      assert output =~ "Total mutants:\e[0m 2"
      assert output =~ "Killed:\e[0m 0"
      assert output =~ "Survived:\e[0m 2"
      assert output =~ "Mutation Score: \e[31m0.0%\e[0m"
    end

    test "reports invalid mutations" do
      results = [
        %{result: :killed, mutation: test_mutation()},
        %{result: :invalid, mutation: test_mutation()}
      ]

      output = capture_io(fn -> Reporter.print_summary(results) end)

      assert output =~ "Invalid:\e[0m 1"
    end

    test "reports timeout mutations" do
      results = [
        %{result: :killed, mutation: test_mutation()},
        %{result: :timeout, mutation: test_mutation()}
      ]

      output = capture_io(fn -> Reporter.print_summary(results) end)

      assert output =~ "Timeout:\e[0m 1"
    end

    test "shows survived mutations details" do
      mutation = %{
        description: "Arithmetic: + to -",
        location: %{file: "lib/calc.ex", line: 5}
      }

      results = [
        %{result: :survived, mutation: mutation}
      ]

      output = capture_io(fn -> Reporter.print_summary(results) end)

      assert output =~ "Survived Mutations"
      assert output =~ "lib/calc.ex:5"
      assert output =~ "Arithmetic: + to -"
    end

    test "handles empty results" do
      output = capture_io(fn -> Reporter.print_summary([]) end)

      assert output =~ "Total mutants:\e[0m 0"
      assert output =~ "Mutation Score: \e[31m0.0%\e[0m"
    end
  end

  describe "print_summary/1 with ANSI color codes" do
    test "prints mutation score in green when >= 80%" do
      results = [
        %{result: :killed, mutation: test_mutation()},
        %{result: :killed, mutation: test_mutation()},
        %{result: :killed, mutation: test_mutation()},
        %{result: :killed, mutation: test_mutation()},
        %{result: :survived, mutation: test_mutation()}
      ]

      output = capture_io(fn -> Reporter.print_summary(results) end)

      assert output =~ "\e[1mMutation Score: \e[32m80.0%\e[0m"
    end

    test "prints mutation score in yellow when >= 60% and < 80%" do
      results = [
        %{result: :killed, mutation: test_mutation()},
        %{result: :killed, mutation: test_mutation()},
        %{result: :killed, mutation: test_mutation()},
        %{result: :survived, mutation: test_mutation()},
        %{result: :survived, mutation: test_mutation()}
      ]

      output = capture_io(fn -> Reporter.print_summary(results) end)

      assert output =~ "\e[1mMutation Score: \e[33m60.0%\e[0m"
    end

    test "prints mutation score in red when < 60%" do
      results = [
        %{result: :killed, mutation: test_mutation()},
        %{result: :survived, mutation: test_mutation()},
        %{result: :survived, mutation: test_mutation()}
      ]

      output = capture_io(fn -> Reporter.print_summary(results) end)

      assert output =~ "\e[1mMutation Score: \e[31m33.33%\e[0m"
    end

    test "prints killed count with green color" do
      results = [%{result: :killed, mutation: test_mutation()}]

      output = capture_io(fn -> Reporter.print_summary(results) end)

      assert output =~ "\e[32mKilled:\e[0m 1"
    end

    test "prints survived count with red color" do
      results = [%{result: :survived, mutation: test_mutation()}]

      output = capture_io(fn -> Reporter.print_summary(results) end)

      assert output =~ "\e[31mSurvived:\e[0m 1"
    end

    test "prints invalid count with yellow color" do
      results = [%{result: :invalid, mutation: test_mutation()}]

      output = capture_io(fn -> Reporter.print_summary(results) end)

      assert output =~ "\e[33mInvalid:\e[0m 1"
    end

    test "prints timeout count with magenta color" do
      results = [%{result: :timeout, mutation: test_mutation()}]

      output = capture_io(fn -> Reporter.print_summary(results) end)

      assert output =~ "\e[35mTimeout:\e[0m 1"
    end

    test "prints title with bold cyan color" do
      results = [%{result: :killed, mutation: test_mutation()}]

      output = capture_io(fn -> Reporter.print_summary(results) end)

      assert output =~ "\e[1m\e[36mMutation Testing Results\e[0m"
    end

    test "prints separators with gray color" do
      results = [%{result: :killed, mutation: test_mutation()}]

      output = capture_io(fn -> Reporter.print_summary(results) end)

      assert output =~ "\e[90m" <> String.duplicate("=", 50) <> "\e[0m"
    end
  end

  describe "print_progress/3" do
    test "prints progress for killed mutation" do
      result = %{result: :killed, mutation: test_mutation()}

      output = capture_io(fn -> Reporter.print_progress(result, 5, 10) end)

      assert output =~ "·"
      refute output =~ "\n"
    end

    test "prints progress for survived mutation" do
      result = %{result: :survived, mutation: test_mutation()}

      output = capture_io(fn -> Reporter.print_progress(result, 3, 10) end)

      assert output =~ "×"
      refute output =~ "\n"
    end

    test "prints progress for invalid mutation" do
      result = %{result: :invalid, mutation: test_mutation()}

      output = capture_io(fn -> Reporter.print_progress(result, 7, 10) end)

      assert output =~ "-"
      refute output =~ "\n"
    end

    test "prints progress for timeout mutation" do
      result = %{result: :timeout, mutation: test_mutation()}

      output = capture_io(fn -> Reporter.print_progress(result, 2, 10) end)

      assert output =~ "?"
      refute output =~ "\n"
    end

    test "prints newline every 80 dots" do
      result = %{result: :killed, mutation: test_mutation()}

      output = capture_io(fn -> Reporter.print_progress(result, 80, 100) end)

      assert output =~ "\n"
    end

    test "prints newline at the end" do
      result = %{result: :killed, mutation: test_mutation()}

      output = capture_io(fn -> Reporter.print_progress(result, 10, 10) end)

      assert output =~ "\n"
    end
  end

  describe "print_progress/3 with ANSI color codes" do
    test "prints killed mutation with green dot" do
      result = %{result: :killed, mutation: test_mutation()}

      output = capture_io(fn -> Reporter.print_progress(result, 5, 10) end)

      assert output =~ "\e[32m·\e[0m"
    end

    test "prints survived mutation with red dot" do
      result = %{result: :survived, mutation: test_mutation()}

      output = capture_io(fn -> Reporter.print_progress(result, 3, 10) end)

      assert output =~ "\e[31m×\e[0m"
    end

    test "prints invalid mutation with yellow dot" do
      result = %{result: :invalid, mutation: test_mutation()}

      output = capture_io(fn -> Reporter.print_progress(result, 7, 10) end)

      assert output =~ "\e[33m-\e[0m"
    end

    test "prints timeout mutation with magenta dot" do
      result = %{result: :timeout, mutation: test_mutation()}

      output = capture_io(fn -> Reporter.print_progress(result, 2, 10) end)

      assert output =~ "\e[35m?\e[0m"
    end
  end

  describe "print_survived_mutations/1 with ANSI color codes" do
    test "prints survived mutations header with bold red color" do
      mutation = %{
        description: "Arithmetic: + to -",
        location: %{file: "lib/calc.ex", line: 5}
      }

      results = [%{result: :survived, mutation: mutation}]

      output = capture_io(fn -> Reporter.print_summary(results) end)

      assert output =~ "\e[1m\e[31mSurvived Mutations:\e[0m"
    end

    test "prints file location with cyan color" do
      mutation = %{
        description: "Arithmetic: + to -",
        location: %{file: "lib/calculator.ex", line: 42}
      }

      results = [%{result: :survived, mutation: mutation}]

      output = capture_io(fn -> Reporter.print_summary(results) end)

      assert output =~ "\e[36mlib/calculator.ex:42\e[0m"
    end

    test "prints mutation description with yellow color" do
      mutation = %{
        description: "Boolean: and to or",
        location: %{file: "lib/logic.ex", line: 10}
      }

      results = [%{result: :survived, mutation: mutation}]

      output = capture_io(fn -> Reporter.print_summary(results) end)

      assert output =~ "\e[33mBoolean: and to or\e[0m"
    end

    test "prints separator with gray dashes" do
      mutation = %{
        description: "Test",
        location: %{file: "lib/test.ex", line: 1}
      }

      results = [%{result: :survived, mutation: mutation}]

      output = capture_io(fn -> Reporter.print_summary(results) end)

      assert output =~ "\e[90m" <> String.duplicate("-", 50) <> "\e[0m"
    end

    test "prints multiple survived mutations with correct colors" do
      mutations = [
        %{
          description: "Arithmetic: + to -",
          location: %{file: "lib/math.ex", line: 5}
        },
        %{
          description: "Comparison: == to !=",
          location: %{file: "lib/compare.ex", line: 15}
        }
      ]

      results =
        Enum.map(mutations, fn mutation ->
          %{result: :survived, mutation: mutation}
        end)

      output = capture_io(fn -> Reporter.print_summary(results) end)

      assert output =~ "\e[36mlib/math.ex:5\e[0m"
      assert output =~ "\e[33mArithmetic: + to -\e[0m"
      assert output =~ "\e[36mlib/compare.ex:15\e[0m"
      assert output =~ "\e[33mComparison: == to !=\e[0m"
    end
  end

  defp test_mutation do
    %{
      description: "Test mutation",
      location: %{file: "test.ex", line: 1}
    }
  end
end
