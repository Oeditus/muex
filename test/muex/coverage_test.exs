defmodule Muex.CoverageTest do
  use ExUnit.Case, async: true

  alias Muex.Coverage

  describe "building and querying an index" do
    setup do
      index =
        Coverage.new()
        |> Coverage.put("lib/a.ex", 10, "test/a_test.exs")
        |> Coverage.put("lib/a.ex", 10, "test/b_test.exs")
        |> Coverage.put("lib/a.ex", 11, "test/a_test.exs")

      %{index: index}
    end

    test "tests_for returns the covering test files for a line, sorted", %{index: index} do
      assert Coverage.tests_for(index, "lib/a.ex", 10) ==
               {:covered, ["test/a_test.exs", "test/b_test.exs"]}

      assert Coverage.tests_for(index, "lib/a.ex", 11) == {:covered, ["test/a_test.exs"]}
    end

    test "tests_for returns :unknown for a line with no coverage data", %{index: index} do
      assert Coverage.tests_for(index, "lib/a.ex", 99) == :unknown
      assert Coverage.tests_for(index, "lib/other.ex", 10) == :unknown
    end

    test "tests_for returns :no_coverage for an executable line no test runs", %{index: index} do
      index = Coverage.put_executable(index, "lib/a.ex", 50)
      assert Coverage.tests_for(index, "lib/a.ex", 50) == :no_coverage
    end

    test "put_executable does not downgrade an already-covered line", %{index: index} do
      index = Coverage.put_executable(index, "lib/a.ex", 10)

      assert Coverage.tests_for(index, "lib/a.ex", 10) ==
               {:covered, ["test/a_test.exs", "test/b_test.exs"]}
    end

    test "put is idempotent for the same (file, line, test)", %{index: index} do
      index = Coverage.put(index, "lib/a.ex", 10, "test/a_test.exs")

      assert Coverage.tests_for(index, "lib/a.ex", 10) ==
               {:covered, ["test/a_test.exs", "test/b_test.exs"]}
    end

    test "covered?/3 reflects whether any test covers the line", %{index: index} do
      assert Coverage.covered?(index, "lib/a.ex", 10)
      refute Coverage.covered?(index, "lib/a.ex", 99)
    end
  end

  test "new/0 is empty" do
    assert Coverage.tests_for(Coverage.new(), "lib/a.ex", 1) == :unknown
  end

  describe "covered_lines/1" do
    test "keeps only the lines a `:cover` line analysis recorded as executed" do
      analysis = [{{SomeMod, 10}, 3}, {{SomeMod, 11}, 0}, {{SomeMod, 12}, 1}]
      assert Coverage.covered_lines(analysis) == [10, 12]
    end

    test "is empty when nothing ran" do
      assert Coverage.covered_lines([{{SomeMod, 5}, 0}]) == []
      assert Coverage.covered_lines([]) == []
    end
  end

  describe "put_lines/4" do
    test "records many lines for one (file, test) at once" do
      index = Coverage.put_lines(Coverage.new(), "lib/a.ex", [10, 12], "test/a_test.exs")

      assert Coverage.tests_for(index, "lib/a.ex", 10) == {:covered, ["test/a_test.exs"]}
      assert Coverage.tests_for(index, "lib/a.ex", 12) == {:covered, ["test/a_test.exs"]}
      assert Coverage.tests_for(index, "lib/a.ex", 11) == :unknown
    end
  end
end
