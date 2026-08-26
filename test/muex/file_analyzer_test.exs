defmodule Muex.FileAnalyzerTest do
  use ExUnit.Case, async: true

  alias Muex.FileAnalyzer

  describe "analyze_file/1" do
    test "does NOT skip modules that implement a behaviour via @behaviour" do
      ast =
        Code.string_to_quoted!(~S'''
        defmodule MyImplementation do
          @behaviour SomeBehaviour

          @impl true
          def foo(x) do
            if x > 0 do
              x + 1
            else
              0
            end
          end
        end
        ''')

      file_entry = %{path: "lib/my_implementation.ex", ast: ast, module_name: MyImplementation}
      result = FileAnalyzer.analyze_file(file_entry)

      assert {:ok, score} = result
      assert score > 0
    end

    test "skips modules that define many callbacks (behaviour definition)" do
      ast =
        Code.string_to_quoted!(~S'''
        defmodule MyBehaviour do
          @callback foo(integer()) :: integer()
          @callback bar(String.t()) :: boolean()
          @callback baz() :: :ok
        end
        ''')

      file_entry = %{path: "lib/my_behaviour.ex", ast: ast, module_name: MyBehaviour}
      assert {:skip, "Behaviour definition"} = FileAnalyzer.analyze_file(file_entry)
    end
  end
end
