defmodule Muex.Mutator.FunctionCall do
  @moduledoc """
  Mutator for function calls.

  Applies mutations to function calls:
  - Remove function calls (replace with nil)
  - Swap function arguments (when there are 2+ args)
  """
  @behaviour Muex.Mutator
  @impl true
  def name do
    "FunctionCall"
  end

  @impl true
  def description do
    "Mutates function calls (remove calls, swap arguments)"
  end

  @impl true
  def mutate(ast, context) do
    case ast do
      {func, meta, args} when is_atom(func) and is_list(args) and args != [] ->
        line = Keyword.get(meta, :line, 0)

        if special_form?(func) do
          []
        else
          mutations = []
          mutations = [build_mutation(nil, "remove #{func}() call", context, line) | mutations]

          mutations =
            if length(args) >= 2 do
              swapped_args = swap_first_two(args)

              [
                build_mutation(
                  {func, meta, swapped_args},
                  "swap arguments in #{func}()",
                  context,
                  line
                )
                | mutations
              ]
            else
              mutations
            end

          Enum.reverse(mutations)
        end

      {{:., dot_meta, [module, func]}, meta, args} when is_list(args) and args != [] ->
        line = Keyword.get(meta, :line, 0)
        mutations = []

        mutations = [
          build_mutation(nil, "remove #{inspect(module)}.#{func}() call", context, line)
          | mutations
        ]

        mutations =
          if length(args) >= 2 do
            swapped_args = swap_first_two(args)

            [
              build_mutation(
                {{:., dot_meta, [module, func]}, meta, swapped_args},
                "swap arguments in #{inspect(module)}.#{func}()",
                context,
                line
              )
              | mutations
            ]
          else
            mutations
          end

        Enum.reverse(mutations)

      _ ->
        []
    end
  end

  defp special_form?(func) do
    func in [
      :def,
      :defp,
      :defmodule,
      :defstruct,
      :import,
      :require,
      :alias,
      :use,
      :quote,
      :unquote,
      :if,
      :unless,
      :case,
      :cond,
      :for,
      :with,
      :receive,
      :try,
      :__block__,
      :=,
      :|>,
      :.,
      :&
    ]
  end

  defp swap_first_two([first, second | rest]) do
    [second, first | rest]
  end

  defp swap_first_two(args) do
    args
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
