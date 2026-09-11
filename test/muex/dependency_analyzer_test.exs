defmodule Muex.DependencyAnalyzerTest do
  use ExUnit.Case, async: true

  alias Muex.DependencyAnalyzer

  describe "analyze/1" do
    test "returns empty map for non-existent directory" do
      assert DependencyAnalyzer.analyze("nonexistent") == %{}
    end

    test "extracts module dependencies from test files" do
      # Use the actual test directory
      result = DependencyAnalyzer.analyze("test")

      # Should return a map
      assert is_map(result)
    end

    @tag :tmp_dir
    test "keys nested module references by their full module name", %{tmp_dir: tmp_dir} do
      test_file = Path.join(tmp_dir, "sample_test.exs")

      File.write!(test_file, """
      defmodule SampleTest do
        use ExUnit.Case
        alias MyApp.Aliased
        import MyApp.Imported

        test "calls" do
          MyApp.Remote.call()
        end
      end
      """)

      result = DependencyAnalyzer.analyze(tmp_dir)

      for module <- [MyApp.Aliased, MyApp.Imported, MyApp.Remote] do
        assert Map.get(result, module) == [test_file]
      end

      refute Map.has_key?(result, :ElixirMyAppAliased)
    end
  end

  describe "get_dependent_tests/2" do
    test "returns empty list for module not in dependency map" do
      dependency_map = %{}
      assert DependencyAnalyzer.get_dependent_tests(NonExistentModule, dependency_map) == []
    end

    test "returns test files for module in dependency map" do
      dependency_map = %{
        MyModule => ["test/my_module_test.exs", "test/integration_test.exs"]
      }

      result = DependencyAnalyzer.get_dependent_tests(MyModule, dependency_map)
      assert match?([_, _], result)
      assert "test/my_module_test.exs" in result
    end
  end

  describe "get_tests_for_mutation/3" do
    test "returns empty list when file not in file_to_module map" do
      mutation = %{location: %{file: "lib/unknown.ex"}}
      dependency_map = %{}
      file_to_module = %{}

      assert DependencyAnalyzer.get_tests_for_mutation(
               mutation,
               dependency_map,
               file_to_module
             ) == []
    end

    test "returns test files for mutation's module" do
      mutation = %{location: %{file: "lib/my_module.ex"}}

      dependency_map = %{
        MyModule => ["test/my_module_test.exs"]
      }

      file_to_module = %{
        "lib/my_module.ex" => MyModule
      }

      result =
        DependencyAnalyzer.get_tests_for_mutation(
          mutation,
          dependency_map,
          file_to_module
        )

      assert result == ["test/my_module_test.exs"]
    end
  end
end
