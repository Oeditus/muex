defmodule Muex.Reporter.PatchTest do
  use ExUnit.Case, async: true

  alias Muex.Reporter.Patch

  test "renders before/after snippets from original_ast and ast" do
    mutation = %{
      original_ast: Code.string_to_quoted!("a + b"),
      ast: Code.string_to_quoted!("a - b")
    }

    assert %{before: "a + b", after: "a - b"} = Patch.of(mutation)
  end

  test "renders bare literal snippets" do
    assert %{before: "41", after: "42"} = Patch.of(%{original_ast: 41, ast: 42})
  end

  test "renders nil replacement for removed calls" do
    mutation = %{original_ast: Code.string_to_quoted!("validate(x)"), ast: nil}
    assert %{before: "validate(x)", after: "nil"} = Patch.of(mutation)
  end

  test "returns nil when original_ast is missing" do
    assert Patch.of(%{ast: 1}) == nil
  end

  test "returns nil when ast is missing" do
    assert Patch.of(%{original_ast: 1}) == nil
  end
end
