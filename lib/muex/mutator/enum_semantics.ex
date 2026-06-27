defmodule Muex.Mutator.EnumSemantics do
  @moduledoc """
  Elixir-specific mutator that swaps `Enum` functions for their semantic
  opposite.

  - `Enum.filter` <-> `Enum.reject`
  - `Enum.all?`   <-> `Enum.any?`
  - `Enum.min`    <-> `Enum.max`
  - `Enum.take`   <-> `Enum.drop`
  - `Enum.map`    <-> `Enum.each`

  These swaps change observable behaviour (the filtered set, the boolean
  result, the selected element, the returned collection) while remaining
  type-compatible, so a surviving mutant points at a test that does not pin
  down which `Enum` operation the code actually relies on.

  Only the function name is rewritten; the call arguments are preserved.
  """

  @behaviour Muex.Mutator

  alias Muex.Mutator.Builders

  @opposites %{
    filter: :reject,
    reject: :filter,
    all?: :any?,
    any?: :all?,
    min: :max,
    max: :min,
    take: :drop,
    drop: :take,
    map: :each,
    each: :map
  }

  @impl true
  def name, do: "EnumSemantics"

  @impl true
  def description, do: "Swaps Enum functions for their semantic opposite"

  @impl true
  def supported_languages, do: [Muex.Language.Elixir]

  @impl true
  def mutate(ast, context),
    do: Builders.module_fn_swap(ast, context, __MODULE__, [:Enum], @opposites)
end
