defmodule MuexTest do
  use ExUnit.Case
  doctest Muex

  test "module loads successfully" do
    assert Code.ensure_loaded?(Muex)
  end
end
