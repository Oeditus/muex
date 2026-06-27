defmodule Muex.Mutator.Builders do
  @moduledoc """
  Shared construction helpers for mutators.

  Mutators describe *what* they change; these helpers own the common mutation
  shape and the recurring AST-rewrite patterns so each mutator stays small.

  Note: `:original_ast` is intentionally never set here — `Muex.Mutator.walk/3`
  stamps it onto every mutation from the matched node.
  """

  @doc """
  Builds a single mutation map. The description is prefixed with the mutator's
  `name/0`; the file falls back to `"unknown"` when the context omits it.
  """
  @spec build(module(), term(), String.t(), map(), non_neg_integer()) :: map()
  def build(mutator, mutated_ast, description, context, line) do
    %{
      ast: mutated_ast,
      mutator: mutator,
      description: "#{mutator.name()}: #{description}",
      location: %{file: Map.get(context, :file, "unknown"), line: line}
    }
  end

  @doc """
  Swaps a binary operator for the value mapped to it in `swaps`.

  Returns a single mutation when the operator is a key in `swaps`, otherwise an
  empty list. The two operands are preserved.
  """
  @spec operator_swap(Macro.t(), map(), module(), %{atom() => atom()}) :: [map()]
  def operator_swap({op, meta, [_left, _right] = args}, context, mutator, swaps) do
    case Map.fetch(swaps, op) do
      {:ok, replacement} ->
        [
          build(
            mutator,
            {replacement, meta, args},
            "#{op} to #{replacement}",
            context,
            line(meta)
          )
        ]

      :error ->
        []
    end
  end

  def operator_swap(_ast, _context, _mutator, _swaps), do: []

  @doc """
  Swaps a module-qualified function call (`Mod.fun(...)`) for `Mod.opposite(...)`.

  Returns a single mutation when `mod` is in `modules` and `fun` is a key in
  `opposites`, otherwise an empty list. The module and arguments are preserved.
  """
  @spec module_fn_swap(Macro.t(), map(), module(), [atom()], %{atom() => atom()}) :: [map()]
  def module_fn_swap(
        {{:., dot_meta, [{:__aliases__, alias_meta, [mod]}, fun]}, call_meta, args},
        context,
        mutator,
        modules,
        opposites
      )
      when is_atom(mod) do
    if mod in modules and is_map_key(opposites, fun) do
      opposite = Map.fetch!(opposites, fun)
      mutated = {{:., dot_meta, [{:__aliases__, alias_meta, [mod]}, opposite]}, call_meta, args}
      [build(mutator, mutated, "#{mod}.#{fun} to #{mod}.#{opposite}", context, line(call_meta))]
    else
      []
    end
  end

  def module_fn_swap(_ast, _context, _mutator, _modules, _opposites), do: []

  @doc """
  Produces one "delete clause" mutation per index in `deletable_positions`.

  `items` is the full list a clause is removed from; `rebuild` turns a reduced
  list back into the enclosing AST node. Labels are 1-based over the deletable
  positions (`delete clause N of M`).
  """
  @spec clause_deletions(
          module(),
          list(),
          [non_neg_integer()],
          (list() -> Macro.t()),
          map(),
          non_neg_integer()
        ) ::
          [map()]
  def clause_deletions(mutator, items, deletable_positions, rebuild, context, line) do
    total = length(deletable_positions)

    deletable_positions
    |> Enum.with_index()
    |> Enum.map(fn {position, nth} ->
      remaining = List.delete_at(items, position)
      build(mutator, rebuild.(remaining), "delete clause #{nth + 1} of #{total}", context, line)
    end)
  end

  defp line(meta), do: Keyword.get(meta, :line, 0)
end
