defmodule Muex.Mutator.GuardTest do
  use ExUnit.Case, async: true

  alias Muex.Mutator.Guard

  # `f(x) when is_integer(x)` => {:when, _, [head, guard]}
  defp when_node(line) do
    head = {:f, [line: line], [{:x, [line: line], nil}]}
    guard = {:is_integer, [line: line], [{:x, [line: line], nil}]}
    {{:when, [line: line], [head, guard]}, head, guard}
  end

  describe "mutate/2" do
    test "removes the guard by replacing it with true" do
      {ast, head, _guard} = when_node(1)

      [mutation] = Guard.mutate(ast, %{file: "test.ex"})

      assert mutation.ast == {:when, [line: 1], [head, true]}
    end

    test "produces a descriptive label" do
      {ast, _head, _guard} = when_node(2)

      [mutation] = Guard.mutate(ast, %{file: "test.ex"})

      assert mutation.description == "Guard: replace guard with true"
    end

    test "includes proper metadata" do
      {ast, _head, _guard} = when_node(10)

      [mutation] = Guard.mutate(ast, %{file: "lib/m.ex"})

      assert mutation.mutator == Muex.Mutator.Guard
      assert mutation.location == %{file: "lib/m.ex", line: 10}
    end

    test "returns empty list for non-guard AST" do
      assert [] = Guard.mutate({:+, [line: 1], [:a, :b]}, %{})
      assert [] = Guard.mutate({:f, [line: 1], [{:x, [line: 1], nil}]}, %{})
    end
  end

  describe "name/0 and description/0" do
    test "name" do
      assert "Guard" = Guard.name()
    end

    test "description mentions guard" do
      assert Guard.description() =~ "guard"
    end
  end

  describe "supported_languages/0" do
    test "supports Elixir" do
      assert Muex.Language.Elixir in Guard.supported_languages()
    end
  end
end
