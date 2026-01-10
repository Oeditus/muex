defmodule Muex.Reporter.JsonTest do
  use ExUnit.Case, async: false

  alias Muex.Reporter.Json

  @moduletag :tmp_dir

  describe "to_json/1" do
    test "generates valid JSON with summary" do
      results = [
        %{
          result: :killed,
          mutation: test_mutation("lib/foo.ex", 1),
          duration_ms: 100,
          error: nil
        },
        %{
          result: :survived,
          mutation: test_mutation("lib/bar.ex", 5),
          duration_ms: 150,
          error: nil
        }
      ]

      json = Json.to_json(results)
      report = Jason.decode!(json)

      assert %{"summary" => summary, "mutations" => mutations} = report
      assert summary["total"] == 2
      assert summary["killed"] == 1
      assert summary["survived"] == 1
      assert summary["invalid"] == 0
      assert summary["timeout"] == 0
      assert summary["mutation_score"] == 50.0
      assert length(mutations) == 2
    end

    test "includes mutation details" do
      results = [
        %{
          result: :killed,
          mutation: test_mutation("lib/test.ex", 10),
          duration_ms: 200,
          error: nil
        }
      ]

      json = Json.to_json(results)
      report = Jason.decode!(json)

      [mutation] = report["mutations"]
      assert mutation["status"] == "killed"
      assert mutation["mutator"] =~ "Muex.Mutator"
      assert mutation["description"] == "Test: mutation"
      assert mutation["location"]["file"] == "lib/test.ex"
      assert mutation["location"]["line"] == 10
      assert mutation["duration_ms"] == 200
      assert mutation["error"] == nil
    end

    test "handles error information" do
      results = [
        %{
          result: :invalid,
          mutation: test_mutation("lib/test.ex", 5),
          duration_ms: 50,
          error: "compilation failed"
        }
      ]

      json = Json.to_json(results)
      report = Jason.decode!(json)

      [mutation] = report["mutations"]
      assert mutation["status"] == "invalid"
      assert mutation["error"] == "compilation failed"
    end

    test "calculates mutation score correctly" do
      results = [
        %{result: :killed, mutation: test_mutation("lib/test.ex", 1), duration_ms: 0, error: nil},
        %{result: :killed, mutation: test_mutation("lib/test.ex", 2), duration_ms: 0, error: nil},
        %{result: :killed, mutation: test_mutation("lib/test.ex", 3), duration_ms: 0, error: nil},
        %{
          result: :survived,
          mutation: test_mutation("lib/test.ex", 4),
          duration_ms: 0,
          error: nil
        }
      ]

      json = Json.to_json(results)
      report = Jason.decode!(json)

      assert report["summary"]["mutation_score"] == 75.0
    end

    test "handles empty results" do
      json = Json.to_json([])
      report = Jason.decode!(json)

      assert report["summary"]["total"] == 0
      assert report["summary"]["mutation_score"] == 0.0
      assert report["mutations"] == []
    end
  end

  describe "generate/2" do
    test "writes JSON to file", %{tmp_dir: tmp_dir} do
      output_file = Path.join(tmp_dir, "report.json")

      results = [
        %{
          result: :killed,
          mutation: test_mutation("lib/test.ex", 1),
          duration_ms: 100,
          error: nil
        }
      ]

      assert :ok = Json.generate(results, output_file: output_file)
      assert File.exists?(output_file)

      content = File.read!(output_file)
      report = Jason.decode!(content)

      assert report["summary"]["total"] == 1
      assert report["summary"]["killed"] == 1
    end

    test "uses default filename when not specified", %{tmp_dir: tmp_dir} do
      File.cd!(tmp_dir, fn ->
        results = [
          %{
            result: :killed,
            mutation: test_mutation("lib/test.ex", 1),
            duration_ms: 100,
            error: nil
          }
        ]

        assert :ok = Json.generate(results)
        assert File.exists?("muex-report.json")
      end)
    end
  end

  defp test_mutation(file, line) do
    %{
      mutator: Muex.Mutator.Arithmetic,
      description: "Test: mutation",
      location: %{
        file: file,
        line: line
      }
    }
  end
end
