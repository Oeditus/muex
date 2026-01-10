defmodule Muex.Language.ElixirTest do
  use ExUnit.Case, async: true

  alias Muex.Language.Elixir, as: ElixirAdapter

  describe "parse/1" do
    test "parses valid Elixir code" do
      source = "defmodule Test do\n  def foo, do: :ok\nend"

      assert {:ok, {:defmodule, _, _}} = ElixirAdapter.parse(source)
    end

    test "returns error for invalid syntax" do
      source = "defmodule Test do"

      assert {:error, _} = ElixirAdapter.parse(source)
    end
  end

  describe "unparse/1" do
    test "converts AST back to source" do
      ast = {:+, [], [1, 2]}

      assert {:ok, source} = ElixirAdapter.unparse(ast)
      assert source == "1 + 2"
    end
  end

  describe "file_extensions/0" do
    test "returns Elixir file extensions" do
      assert [".ex", ".exs"] = ElixirAdapter.file_extensions()
    end
  end

  describe "test_file_pattern/0" do
    test "returns regex for test files" do
      pattern = ElixirAdapter.test_file_pattern()

      assert Regex.match?(pattern, "test/my_test.exs")
      assert Regex.match?(pattern, "test/my_test.ex")
      refute Regex.match?(pattern, "lib/my_module.ex")
    end
  end
end
