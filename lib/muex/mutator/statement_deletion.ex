defmodule Muex.Mutator.StatementDeletion do
  @moduledoc """
  Mutator that removes individual statements from blocks.

  Targets `__block__` nodes with two or more statements. For each
  non-final statement, produces a mutation that deletes it from the block.
  The final statement (the return value) is left to the ReturnValue mutator.

  This is one of the highest-value mutation operators: if deleting a
  statement doesn't cause any test to fail, that statement is either
  dead code or untested side-effect logic.

  ## Module attributes are not mutated

  A `defmodule` body is itself a `__block__`, so without a guard this
  mutator would delete `@moduledoc` / `@doc` / `@spec` / `@type` /
  `@behaviour` / constant attributes. Deleting a non-executable attribute
  (docs, specs, types) has no runtime effect, so it can never be caught by
  a test — it only manufactures unkillable survivors that drag the score
  down without pointing at a real coverage gap. Deleting a *used* constant
  attribute (`@timeout 5_000`) just yields a guaranteed compile error
  (an "invalid" mutant). Neither is a meaningful test-quality signal, so
  `@`-attribute statements are skipped entirely.
  """
  @behaviour Muex.Mutator

  @impl true
  def name, do: "StatementDeletion"

  @impl true
  def description, do: "Deletes individual statements from blocks"

  @impl true
  def supported_languages, do: [Muex.Language.Elixir, Muex.Language.Erlang]

  @impl true
  def mutate({:__block__, meta, statements}, context) when length(statements) >= 2 do
    last_idx = length(statements) - 1

    statements
    |> Enum.with_index()
    # Skip the return value (ReturnValue handles it) and module attributes (see
    # the moduledoc — deleting them only manufactures unkillable survivors).
    |> Enum.reject(fn {stmt, idx} -> idx == last_idx or module_attribute?(stmt) end)
    |> Enum.map(fn {stmt, idx} ->
      remaining = List.delete_at(statements, idx)
      mutated_ast = simplify_block(meta, remaining)
      stmt_line = get_statement_line(stmt)

      build_mutation(
        mutated_ast,
        "delete statement #{idx + 1} of #{length(statements)}",
        context,
        stmt_line
      )
    end)
  end

  def mutate(_ast, _context), do: []

  @impl true
  # A clause deletion is equivalent when the deleted clause's inputs are fully
  # absorbed by the *next* clause of the same function (same name/arity) that is
  # an unguarded catch-all (all bare-variable args) carrying an identical body
  # bound at the same argument positions. Any input that reached the deleted
  # clause falls through to that catch-all after deletion and yields the same
  # result, so no test can tell the two apart.
  #
  # Example — deleting the explicit clause here is equivalent, because the
  # `_msg` catch-all immediately below returns the same `{:noreply, state}`:
  #
  #     def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}
  #     def handle_info(_msg, state), do: {:noreply, state}
  #
  # Sound by construction: anything we can't prove equivalent is treated as
  # killable (returns false), matching Muex.Equivalence's no-false-positives
  # contract.
  def equivalent?(%{original_ast: {:__block__, _, orig}, ast: mutated}) when is_list(orig) do
    case orig -- block_statements(mutated) do
      [deleted] -> absorbed_by_next_catch_all?(deleted, orig)
      _ -> false
    end
  end

  def equivalent?(_mutation), do: false

  defp block_statements({:__block__, _meta, stmts}), do: stmts
  defp block_statements(single), do: [single]

  defp absorbed_by_next_catch_all?(deleted, orig) do
    with {name, arity, d_args, d_body, _guarded} <- clause_info(deleted),
         next when not is_nil(next) <- next_clause_after(orig, deleted, name, arity),
         {^name, ^arity, c_args, c_body, false} <- clause_info(next),
         true <- catch_all_args?(c_args),
         true <- bodies_equal?(d_body, c_body),
         true <- bindings_consistent?(d_args, c_args, d_body) do
      true
    else
      _ -> false
    end
  end

  # {name, arity, args, body, guarded?} for a `def`/`defp` clause with a `do:`
  # body, or nil for anything else (multi-clause `do/else`, bodiless heads, …).
  defp clause_info({kind, _meta, [head, [{:do, body}]]}) when kind in [:def, :defp] do
    case head do
      {:when, _, [{name, _, args}, _guard]} when is_atom(name) and is_list(args) ->
        {name, length(args), args, body, true}

      {name, _, args} when is_atom(name) and is_list(args) ->
        {name, length(args), args, body, false}

      _ ->
        nil
    end
  end

  defp clause_info(_), do: nil

  # The first statement after `deleted` that is a clause of the same function.
  # Inputs that reached `deleted` fall through to this clause once it is gone.
  defp next_clause_after(orig, deleted, name, arity) do
    orig
    |> Enum.drop_while(&(&1 != deleted))
    |> Enum.drop(1)
    |> Enum.find(fn stmt ->
      match?({^name, ^arity, _, _, _}, clause_info(stmt))
    end)
  end

  defp catch_all_args?(args), do: Enum.all?(args, &bare_var?/1)

  defp bare_var?({name, _meta, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp bare_var?(_), do: false

  defp bodies_equal?(a, b), do: strip_meta(a) == strip_meta(b)

  defp strip_meta(ast) do
    Macro.prewalk(ast, fn
      {form, _meta, args} -> {form, [], args}
      other -> other
    end)
  end

  # Every variable the shared body reads must be bound at the *same* argument
  # position (and name) in both clauses, so the catch-all feeds it the same
  # value the deleted clause would have.
  defp bindings_consistent?(d_args, c_args, body) do
    d_pos = var_positions(d_args)
    c_pos = var_positions(c_args)

    Enum.all?(free_vars(body), fn v ->
      Map.has_key?(d_pos, v) and Map.get(d_pos, v) == Map.get(c_pos, v)
    end)
  end

  defp var_positions(args) do
    args
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {arg, i}, acc ->
      if bare_var?(arg), do: Map.put(acc, var_name(arg), i), else: acc
    end)
  end

  defp free_vars(body) do
    {_ast, vars} =
      Macro.prewalk(body, MapSet.new(), fn node, acc ->
        if bare_var?(node), do: {node, MapSet.put(acc, var_name(node))}, else: {node, acc}
      end)

    MapSet.to_list(vars)
  end

  defp var_name({name, _meta, _ctx}), do: name

  # Any `@`-prefixed module attribute (see the moduledoc).
  defp module_attribute?({:@, _meta, _args}), do: true
  defp module_attribute?(_), do: false

  # A block with one remaining statement collapses to that statement.
  defp simplify_block(_meta, [single]), do: single
  defp simplify_block(meta, stmts), do: {:__block__, meta, stmts}

  defp get_statement_line({_form, meta, _args}) when is_list(meta) do
    Keyword.get(meta, :line, 0)
  end

  defp get_statement_line(_), do: 0

  defp build_mutation(mutated_ast, description, context, line) do
    %{
      ast: mutated_ast,
      mutator: __MODULE__,
      description: "#{name()}: #{description}",
      location: %{file: Map.get(context, :file, "unknown"), line: line}
    }
  end
end
