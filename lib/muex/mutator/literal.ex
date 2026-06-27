defmodule Muex.Mutator.Literal do
  @moduledoc """
  Mutator for literal values.

  Applies mutations to literals:
  - Numeric literals: increment/decrement by 1
  - String literals: empty string, change character
  - List literals: empty list
  - Atom literals: change to different atom (except special atoms)

  ## Location

  Bare literals carry no AST metadata of their own, so this mutator reads
  the enclosing source line from `context[:line]` (populated by
  `Muex.Mutator.walk/3`), falling back to `0` when no context line is
  available. This lets reports point at the literal's actual line instead
  of `line: 0`.

  ## Skipped atoms

  Module alias segments (atoms whose name starts with an uppercase letter,
  e.g. `:Phoenix`, `:Component`) are never mutated: they are structural
  metadata, and mutating them produces invalid mutants. The traversal in
  `Muex.Mutator.walk/3` already prunes `__aliases__` subtrees; this guard
  is a defensive backstop for alias atoms reached by other paths. The
  special atoms `nil`, `true`, `false`, `:ok`, and `:error` are likewise
  left untouched.
  """
  @behaviour Muex.Mutator
  @special_atoms [nil, true, false, :ok, :error]
  @impl true
  def name do
    "Literal"
  end

  @impl true
  def description do
    "Mutates literal values (numbers, strings, lists, atoms)"
  end

  @impl true
  def supported_languages, do: [Muex.Language.Elixir, Muex.Language.Erlang]

  @impl true
  def mutate(ast, context) do
    case ast do
      n when is_integer(n) ->
        [
          build_mutation(n + 1, "#{n} to #{n + 1} (increment)", context),
          build_mutation(n - 1, "#{n} to #{n - 1} (decrement)", context)
        ]

      n when is_float(n) ->
        [
          build_mutation(n + 1.0, "#{n} to #{n + 1.0} (increment)", context),
          build_mutation(n - 1.0, "#{n} to #{n - 1.0} (decrement)", context)
        ]

      s when is_binary(s) and s != "" ->
        [
          build_mutation("", "\"#{s}\" to \"\" (empty string)", context),
          build_mutation(s <> "x", "\"#{s}\" to \"#{s}x\" (append char)", context)
        ]

      "" ->
        [build_mutation("x", "\"\" to \"x\" (add char)", context)]

      [] ->
        [build_mutation([:mutated], "[] to [:mutated]", context)]

      atom when is_atom(atom) and atom not in @special_atoms ->
        if alias_atom?(atom) do
          []
        else
          [build_mutation(:mutated_atom, ":#{atom} to :mutated_atom", context)]
        end

      _ ->
        []
    end
  end

  # Module alias segments start with an uppercase letter (e.g. `:Phoenix`).
  defp alias_atom?(atom) do
    case Atom.to_string(atom) do
      <<first::utf8, _rest::binary>> -> first in ?A..?Z
      _ -> false
    end
  end

  defp build_mutation(mutated_ast, description, context) do
    %{
      ast: mutated_ast,
      mutator: __MODULE__,
      description: "#{name()}: #{description}",
      location: %{file: Map.get(context, :file, "unknown"), line: Map.get(context, :line, 0)}
    }
  end
end
