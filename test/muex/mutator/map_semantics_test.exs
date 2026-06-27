defmodule Muex.Mutator.MapSemanticsTest do
  use ExUnit.Case, async: true

  alias Muex.Mutator.MapSemantics

  # Build the AST for `<Mod>.<fun>(m, k, v)`.
  defp call(mod, fun, line) do
    {{:., [line: line], [{:__aliases__, [line: line], [mod]}, fun]}, [line: line],
     [{:m, [line: line], nil}, {:k, [line: line], nil}, {:v, [line: line], nil}]}
  end

  defp swapped_fun([%{ast: {{:., _, [{:__aliases__, _, [_mod]}, fun]}, _, _}}]), do: fun

  describe "mutate/2" do
    test "swaps Map.put <-> Map.put_new" do
      assert MapSemantics.mutate(call(:Map, :put, 1), %{}) |> swapped_fun() == :put_new
      assert MapSemantics.mutate(call(:Map, :put_new, 1), %{}) |> swapped_fun() == :put
    end

    test "swaps Keyword.put <-> Keyword.put_new" do
      assert MapSemantics.mutate(call(:Keyword, :put, 1), %{}) |> swapped_fun() == :put_new
      assert MapSemantics.mutate(call(:Keyword, :put_new, 1), %{}) |> swapped_fun() == :put
    end

    test "keeps the same module and arguments" do
      [mutation] = MapSemantics.mutate(call(:Map, :put, 7), %{file: "test.ex"})
      {{:., _, [{:__aliases__, _, [mod]}, :put_new]}, _, args} = mutation.ast
      assert mod == :Map
      assert args == [{:m, [line: 7], nil}, {:k, [line: 7], nil}, {:v, [line: 7], nil}]
    end

    test "produces a descriptive label and metadata" do
      [mutation] = MapSemantics.mutate(call(:Map, :put, 9), %{file: "lib/m.ex"})
      assert mutation.description == "MapSemantics: Map.put to Map.put_new"
      assert mutation.mutator == Muex.Mutator.MapSemantics
      assert mutation.location == %{file: "lib/m.ex", line: 9}
    end

    test "ignores Map functions without a defined opposite" do
      assert [] = MapSemantics.mutate(call(:Map, :get, 1), %{})
    end

    test "ignores unrelated modules" do
      assert [] = MapSemantics.mutate(call(:Enum, :put, 1), %{})
    end

    test "returns empty list for unrelated AST" do
      assert [] = MapSemantics.mutate({:+, [line: 1], [:a, :b]}, %{})
    end
  end

  describe "name/0 and description/0" do
    test "name" do
      assert "MapSemantics" = MapSemantics.name()
    end

    test "description mentions put_new or Map" do
      desc = MapSemantics.description()
      assert desc =~ "put_new" or desc =~ "Map"
    end
  end

  describe "supported_languages/0" do
    test "supports Elixir only" do
      assert MapSemantics.supported_languages() == [Muex.Language.Elixir]
    end
  end
end
