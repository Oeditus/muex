defmodule Muex.Reporter.HtmlTest do
  use ExUnit.Case, async: true

  alias Muex.Reporter.Html

  @moduletag :tmp_dir

  describe "generate/2" do
    test "lists the test files each mutant was run against", %{tmp_dir: tmp_dir} do
      output_file = Path.join(tmp_dir, "report.html")

      results = [
        %{
          result: :survived,
          mutation: test_mutation(),
          duration_ms: 0,
          error: nil,
          test_files: ["test/a_test.exs", "test/<b>_test.exs"]
        }
      ]

      assert :ok = Html.generate(results, output_file: output_file)
      html = File.read!(output_file)

      assert html =~ "Test files: test/a_test.exs, test/&lt;b&gt;_test.exs"
    end

    test "omits the test-files line when no test ran", %{tmp_dir: tmp_dir} do
      output_file = Path.join(tmp_dir, "report.html")
      results = [%{result: :invalid, mutation: test_mutation(), duration_ms: 0, error: nil}]

      assert :ok = Html.generate(results, output_file: output_file)

      refute File.read!(output_file) =~ "Test files:"
    end
  end

  describe "generate/2 with a partial run" do
    test "shows a banner saying how many mutants ran", %{tmp_dir: tmp_dir} do
      output_file = Path.join(tmp_dir, "report.html")
      results = [%{result: :killed, mutation: test_mutation(), duration_ms: 0, error: nil}]
      partial = %{mutations_run: 14, mutations_total: 30}

      assert :ok = Html.generate(results, output_file: output_file, partial: partial)

      assert File.read!(output_file) =~ "PARTIAL: 14 of 30 mutants run"
    end

    test "has no banner for a complete run", %{tmp_dir: tmp_dir} do
      output_file = Path.join(tmp_dir, "report.html")
      results = [%{result: :killed, mutation: test_mutation(), duration_ms: 0, error: nil}]

      assert :ok = Html.generate(results, output_file: output_file)

      refute File.read!(output_file) =~ "PARTIAL"
    end
  end

  defp test_mutation do
    %{
      mutator: Muex.Mutator.Arithmetic,
      description: "Arithmetic: + to -",
      location: %{file: "lib/calc.ex", line: 5}
    }
  end
end
