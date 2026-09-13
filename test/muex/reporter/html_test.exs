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

  defp test_mutation do
    %{
      mutator: Muex.Mutator.Arithmetic,
      description: "Arithmetic: + to -",
      location: %{file: "lib/calc.ex", line: 5}
    }
  end
end
