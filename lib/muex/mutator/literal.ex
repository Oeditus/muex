defmodule Muex.Mutator.Literal do
  @moduledoc """
  Mutator for literal values.

  Applies mutations to literals:
  - Numeric literals: increment/decrement by 1
  - String literals: empty string, change character
  - List literals: empty list
  - Atom literals: change to different atom (except special atoms)
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
  def mutate(ast, context) do
    case ast do
      n when is_integer(n) ->
        [
          build_mutation(n + 1, "#{n} to #{n + 1} (increment)", context, 0),
          build_mutation(n - 1, "#{n} to #{n - 1} (decrement)", context, 0)
        ]

      n when is_float(n) ->
        [
          build_mutation(n + 1.0, "#{n} to #{n + 1.0} (increment)", context, 0),
          build_mutation(n - 1.0, "#{n} to #{n - 1.0} (decrement)", context, 0)
        ]

      s when is_binary(s) and s != "" ->
        [
          build_mutation("", "\"#{s}\" to \"\" (empty string)", context, 0),
          build_mutation(s <> "x", "\"#{s}\" to \"#{s}x\" (append char)", context, 0)
        ]

      "" ->
        [build_mutation("x", "\"\" to \"x\" (add char)", context, 0)]

      [] ->
        [build_mutation([:mutated], "[] to [:mutated]", context, 0)]

      atom when is_atom(atom) and atom not in @special_atoms ->
        [build_mutation(:mutated_atom, ":#{atom} to :mutated_atom", context, 0)]

      _ ->
        []
    end
  end

  defp build_mutation(mutated_ast, description, context, line) do
    %{
      ast: mutated_ast,
      mutator: __MODULE__,
      description: "#{name()}: #{description}",
      location: %{file: Map.get(context, :file, "unknown"), line: line}
    }
  end
end
