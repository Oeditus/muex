defmodule Muex.Mutator.ExtendedMath do
  @moduledoc """
  Mutator for integer division/remainder and bitwise operators that the
  `Arithmetic` mutator (`+`, `-`, `*`, `/`) does not cover.

  Swaps each operator for a related one with different behaviour:

  - `rem` <-> `div`
  - `band` <-> `bor`  (and the operator forms `&&&` <-> `|||`)
  - `bsl` <-> `bsr`   (and the operator forms `<<<` <-> `>>>`)

  Only binary (two-operand) forms are mutated. Module-qualified calls such as
  `Bitwise.band/2` are left alone; the imported operator/function forms are the
  common case.
  """

  @behaviour Muex.Mutator

  alias Muex.Mutator.Builders

  @swaps %{
    rem: :div,
    div: :rem,
    band: :bor,
    bor: :band,
    bsl: :bsr,
    bsr: :bsl,
    &&&: :|||,
    |||: :&&&,
    <<<: :>>>,
    >>>: :<<<
  }

  @impl true
  def name, do: "ExtendedMath"

  @impl true
  def description, do: "Mutates integer division/remainder and bitwise operators"

  @impl true
  def supported_languages, do: [Muex.Language.Elixir, Muex.Language.Erlang]

  @impl true
  def mutate(ast, context), do: Builders.operator_swap(ast, context, __MODULE__, @swaps)
end
