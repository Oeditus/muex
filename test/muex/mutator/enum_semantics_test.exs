defmodule Muex.Mutator.EnumSemanticsTest do
  use ExUnit.Case, async: true

  alias Muex.Mutator.EnumSemantics

  # Helper: build the AST for `Enum.<fun>(arg1, arg2)`.
  defp enum_call(fun, line) do
    {{:., [line: line], [{:__aliases__, [line: line], [:Enum]}, fun]}, [line: line],
     [{:list, [line: line], nil}, {:f, [line: line], nil}]}
  end

  defp mutated_fun([%{ast: {{:., _, [{:__aliases__, _, [:Enum]}, fun]}, _, _}}]), do: fun

  describe "mutate/2" do
    test "swaps Enum.filter -> Enum.reject" do
      mutations = EnumSemantics.mutate(enum_call(:filter, 1), %{file: "test.ex"})
      assert mutated_fun(mutations) == :reject
    end

    test "swaps Enum.reject -> Enum.filter" do
      assert EnumSemantics.mutate(enum_call(:reject, 1), %{}) |> mutated_fun() == :filter
    end

    test "swaps Enum.all? -> Enum.any?" do
      assert EnumSemantics.mutate(enum_call(:all?, 1), %{}) |> mutated_fun() == :any?
    end

    test "swaps Enum.any? -> Enum.all?" do
      assert EnumSemantics.mutate(enum_call(:any?, 1), %{}) |> mutated_fun() == :all?
    end

    test "swaps Enum.min -> Enum.max" do
      assert EnumSemantics.mutate(enum_call(:min, 1), %{}) |> mutated_fun() == :max
    end

    test "swaps Enum.take -> Enum.drop" do
      assert EnumSemantics.mutate(enum_call(:take, 1), %{}) |> mutated_fun() == :drop
    end

    test "swaps Enum.map -> Enum.each" do
      assert EnumSemantics.mutate(enum_call(:map, 1), %{}) |> mutated_fun() == :each
    end

    test "every supported function swaps to its opposite (both directions)" do
      swaps = [
        {:filter, :reject},
        {:reject, :filter},
        {:all?, :any?},
        {:any?, :all?},
        {:min, :max},
        {:max, :min},
        {:take, :drop},
        {:drop, :take},
        {:map, :each},
        {:each, :map}
      ]

      for {fun, opposite} <- swaps do
        assert EnumSemantics.mutate(enum_call(fun, 1), %{}) |> mutated_fun() == opposite
      end
    end

    test "preserves the call arguments" do
      [mutation] = EnumSemantics.mutate(enum_call(:filter, 7), %{file: "test.ex"})
      {{:., _, [{:__aliases__, _, [:Enum]}, :reject]}, _, args} = mutation.ast
      assert args == [{:list, [line: 7], nil}, {:f, [line: 7], nil}]
    end

    test "produces a descriptive label and metadata" do
      [mutation] = EnumSemantics.mutate(enum_call(:filter, 9), %{file: "lib/m.ex"})
      assert mutation.description == "EnumSemantics: Enum.filter to Enum.reject"
      assert mutation.mutator == Muex.Mutator.EnumSemantics
      assert mutation.location == %{file: "lib/m.ex", line: 9}
    end

    test "ignores Enum functions without a defined opposite" do
      assert [] = EnumSemantics.mutate(enum_call(:sort, 1), %{})
    end

    test "ignores non-Enum module calls" do
      ast =
        {{:., [line: 1], [{:__aliases__, [line: 1], [:List]}, :filter]}, [line: 1],
         [{:l, [line: 1], nil}]}

      assert [] = EnumSemantics.mutate(ast, %{})
    end

    test "returns empty list for unrelated AST" do
      assert [] = EnumSemantics.mutate({:+, [line: 1], [:a, :b]}, %{})
    end
  end

  describe "name/0 and description/0" do
    test "name" do
      assert "EnumSemantics" = EnumSemantics.name()
    end

    test "description mentions Enum" do
      assert EnumSemantics.description() =~ "Enum"
    end
  end

  describe "supported_languages/0" do
    test "supports Elixir only (Enum is an Elixir module)" do
      assert EnumSemantics.supported_languages() == [Muex.Language.Elixir]
    end
  end
end
