defmodule Muex.Mutator.MapSemantics do
  @moduledoc """
  Elixir-specific mutator that swaps `put`/`put_new` on `Map` and `Keyword`.

  - `Map.put` <-> `Map.put_new`
  - `Keyword.put` <-> `Keyword.put_new`

  `put` always writes; `put_new` writes only when the key is absent. They have
  the same arity and return type, so a surviving mutant means no test exercises
  the case where the key is already present — a common real-world bug.

  Only module-qualified calls on `Map`/`Keyword` are matched; the call
  arguments are preserved.
  """

  @behaviour Muex.Mutator

  alias Muex.Mutator.Builders

  @opposites %{put: :put_new, put_new: :put}
  @modules [:Map, :Keyword]

  @impl true
  def name, do: "MapSemantics"

  @impl true
  def description, do: "Swaps Map/Keyword put for put_new"

  @impl true
  def supported_languages, do: [Muex.Language.Elixir]

  @impl true
  def mutate(ast, context),
    do: Builders.module_fn_swap(ast, context, __MODULE__, @modules, @opposites)
end
