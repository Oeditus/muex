defmodule Muex.Mutator.PipeTest do
  use ExUnit.Case, async: true

  alias Muex.Mutator.Pipe

  describe "mutate/2" do
    test "drops the trailing stage of a pipe (x |> f -> x)" do
      left = {:x, [line: 1], nil}
      ast = {:|>, [line: 1], [left, {:f, [line: 1], []}]}

      [mutation] = Pipe.mutate(ast, %{file: "test.ex"})

      assert mutation.ast == left
      assert mutation.description == "Pipe: drop pipe stage"
    end

    test "drops only the outermost stage at a given node (nested handled by walk)" do
      # `a |> f |> g` => {:|>, _, [{:|>, _, [a, f]}, g]}
      inner = {:|>, [line: 2], [{:a, [line: 2], nil}, {:f, [line: 2], []}]}
      ast = {:|>, [line: 2], [inner, {:g, [line: 2], []}]}

      [mutation] = Pipe.mutate(ast, %{file: "test.ex"})

      assert mutation.ast == inner
    end

    test "includes proper metadata" do
      ast = {:|>, [line: 10], [{:x, [line: 10], nil}, {:f, [line: 10], []}]}

      [mutation] = Pipe.mutate(ast, %{file: "lib/m.ex"})

      assert mutation.mutator == Muex.Mutator.Pipe
      assert mutation.location == %{file: "lib/m.ex", line: 10}
    end

    test "returns empty list for non-pipe AST" do
      assert [] = Pipe.mutate({:+, [line: 1], [:a, :b]}, %{})
      assert [] = Pipe.mutate({:f, [line: 1], []}, %{})
    end
  end

  describe "name/0 and description/0" do
    test "name" do
      assert "Pipe" = Pipe.name()
    end

    test "description mentions pipe" do
      assert Pipe.description() =~ "pipe"
    end
  end

  describe "supported_languages/0" do
    test "supports Elixir only (|> is an Elixir construct)" do
      assert Pipe.supported_languages() == [Muex.Language.Elixir]
    end
  end
end
