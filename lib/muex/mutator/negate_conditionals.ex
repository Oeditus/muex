defmodule Muex.Mutator.NegateConditionals do
  @moduledoc """
  Mutator that replaces a relational operator with its logical complement.

  - `<`  -> `>=`
  - `>`  -> `<=`
  - `<=` -> `>`
  - `>=` -> `<`

  This is PITest's "Negate Conditionals" semantics: each mutation flips the
  truth value of the condition for every input. It deliberately leaves the
  equality operators (`==`, `!=`, `===`, `!==`) to `Muex.Mutator.Comparison`
  and the directional/boundary shifts (e.g. `<` -> `>`) to that mutator too,
  so the two mutators compose without producing duplicate mutants.
  """

  @behaviour Muex.Mutator

  alias Muex.Mutator.Builders

  @complements %{<: :>=, >: :<=, <=: :>, >=: :<}

  @impl true
  def name, do: "NegateConditionals"

  @impl true
  def description, do: "Replaces a relational operator with its logical complement"

  @impl true
  def supported_languages, do: [Muex.Language.Elixir, Muex.Language.Erlang]

  @impl true
  def mutate(ast, context), do: Builders.operator_swap(ast, context, __MODULE__, @complements)
end
