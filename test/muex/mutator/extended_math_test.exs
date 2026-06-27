defmodule Muex.Mutator.ExtendedMathTest do
  use ExUnit.Case, async: true

  alias Muex.Mutator.ExtendedMath

  defp swap_op([%{ast: {op, _, _}}]), do: op

  describe "mutate/2" do
    test "swaps rem <-> div" do
      assert ExtendedMath.mutate({:rem, [line: 1], [:a, :b]}, %{}) |> swap_op() == :div
      assert ExtendedMath.mutate({:div, [line: 1], [:a, :b]}, %{}) |> swap_op() == :rem
    end

    test "swaps bitwise function forms band <-> bor and bsl <-> bsr" do
      assert ExtendedMath.mutate({:band, [line: 1], [:a, :b]}, %{}) |> swap_op() == :bor
      assert ExtendedMath.mutate({:bor, [line: 1], [:a, :b]}, %{}) |> swap_op() == :band
      assert ExtendedMath.mutate({:bsl, [line: 1], [:a, :b]}, %{}) |> swap_op() == :bsr
      assert ExtendedMath.mutate({:bsr, [line: 1], [:a, :b]}, %{}) |> swap_op() == :bsl
    end

    test "swaps bitwise operator forms &&& <-> ||| and <<< <-> >>>" do
      assert ExtendedMath.mutate({:&&&, [line: 1], [:a, :b]}, %{}) |> swap_op() == :|||
      assert ExtendedMath.mutate({:|||, [line: 1], [:a, :b]}, %{}) |> swap_op() == :&&&
      assert ExtendedMath.mutate({:<<<, [line: 1], [:a, :b]}, %{}) |> swap_op() == :>>>
      assert ExtendedMath.mutate({:>>>, [line: 1], [:a, :b]}, %{}) |> swap_op() == :<<<
    end

    test "preserves operands" do
      [mutation] = ExtendedMath.mutate({:rem, [line: 5], [:a, :b]}, %{file: "test.ex"})
      assert {:div, [line: 5], [:a, :b]} = mutation.ast
    end

    test "produces a descriptive label and metadata" do
      [mutation] = ExtendedMath.mutate({:rem, [line: 9], [:a, :b]}, %{file: "lib/m.ex"})
      assert mutation.description == "ExtendedMath: rem to div"
      assert mutation.mutator == Muex.Mutator.ExtendedMath
      assert mutation.location == %{file: "lib/m.ex", line: 9}
    end

    test "ignores basic arithmetic (left to Arithmetic mutator)" do
      assert [] = ExtendedMath.mutate({:+, [line: 1], [:a, :b]}, %{})
      assert [] = ExtendedMath.mutate({:*, [line: 1], [:a, :b]}, %{})
    end

    test "ignores unary or wrong-arity calls" do
      assert [] = ExtendedMath.mutate({:rem, [line: 1], [:a]}, %{})
      assert [] = ExtendedMath.mutate({:foo, [line: 1], [:a, :b]}, %{})
    end
  end

  describe "name/0 and description/0" do
    test "name" do
      assert "ExtendedMath" = ExtendedMath.name()
    end

    test "description mentions bitwise or division" do
      desc = ExtendedMath.description()
      assert desc =~ "bitwise" or desc =~ "division"
    end
  end

  describe "supported_languages/0" do
    test "supports Elixir" do
      assert Muex.Language.Elixir in ExtendedMath.supported_languages()
    end
  end
end
