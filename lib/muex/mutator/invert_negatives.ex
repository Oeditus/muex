defmodule Muex.Mutator.InvertNegatives do
  @moduledoc """
  Mutator that inverts unary negation.

  Replaces a unary negation with its operand:

  - `-x` -> `x`

  This is the classic PITest "Invert Negatives" mutator. It targets only the
  unary minus (`{:-, meta, [operand]}`); binary subtraction (`a - b`) is left
  to the `Muex.Mutator.Arithmetic` mutator.
  """

  @behaviour Muex.Mutator

  alias Muex.Mutator.Builders

  @impl true
  def name, do: "InvertNegatives"

  @impl true
  def description, do: "Inverts unary negation (-x becomes x)"

  @impl true
  def supported_languages, do: [Muex.Language.Elixir, Muex.Language.Erlang]

  @impl true
  def mutate({:-, meta, [operand]}, context) do
    [Builders.build(__MODULE__, operand, "-x to x", context, Keyword.get(meta, :line, 0))]
  end

  def mutate(_ast, _context), do: []
end
