defmodule Muex.Mutator do
  @moduledoc """
  Behaviour for mutation operators that transform AST nodes.

  Mutators implement specific mutation strategies (e.g., arithmetic operators,
  boolean operators, literals) and return a list of possible mutations for a given AST.

  Each mutator declares which languages it supports via `supported_languages/0`.
  Mutators targeting the same AST family (e.g., Elixir and Erlang both use BEAM
  AST) can declare support for multiple languages.

  ## Traversal and Pruning

  `walk/3` performs a context-aware, pre-order traversal of the AST. It threads
  the nearest enclosing source line through `context[:line]` and prunes subtrees
  that should never be mutated (module aliases, `use`/`import`/`alias`/`require`,
  documentation and typespec attributes, and keyword/option keys). Callers can
  prune additional framework DSL calls via `context[:skip_calls]`. See `walk/3`
  for the full set of rules.

  ## Equivalent Mutations

  Mutators can declare that a generated mutation is semantically equivalent to the
  original code — meaning no test can ever kill it. This avoids polluting mutation
  scores with false negatives.

  There are two ways to mark equivalence:

  1. **At generation time** — set `equivalent: true` in the mutation map returned
     by `mutate/2`. Use this when the mutator knows at generation time that the
     mutation is equivalent (e.g., swapping arguments to a commutative operator).

  2. **Via the `equivalent?/1` callback** — implement this for more complex
     analysis that needs to inspect the full mutation map. The default
     implementation checks the `:equivalent` key.

  ## Example

      defmodule Muex.Mutator.MyMutator do
        @behaviour Muex.Mutator

        @impl true
        def mutate(ast, _context) do
          # Return list of mutated AST variants
          [mutated_ast_1, mutated_ast_2]
        end

        @impl true
        def name, do: "My Mutator"

        @impl true
        def description, do: "Mutates specific AST patterns"

        @impl true
        def supported_languages, do: [Muex.Language.Elixir, Muex.Language.Erlang]

        # Optional: override for complex equivalence detection
        @impl true
        def equivalent?(%{description: "swap arguments in +()" <> _}), do: true
        def equivalent?(_mutation), do: false
      end
  """
  @typedoc """
  Represents a single mutation with its metadata.

  The `:equivalent` key is optional. When `true`, the mutation is considered
  semantically equivalent to the original and will be filtered out by the optimizer.
  """
  @type mutation :: %{
          ast: term(),
          original_ast: term(),
          mutator: module(),
          description: String.t(),
          location: %{file: String.t(), line: non_neg_integer()}
        }

  @doc """
  Applies mutations to the given AST.

  ## Parameters

    - `ast` - The AST to mutate
    - `context` - Map containing additional context (file path, line number, etc.)

  ## Returns

    List of `mutation` maps, each representing a possible mutation
  """
  @callback mutate(ast :: term(), context :: map()) :: [mutation()]

  @doc """
  Returns the name of the mutator.
  """
  @callback name() :: String.t()

  @doc """
  Returns a description of what this mutator does.
  """
  @callback description() :: String.t()

  @doc """
  Returns the list of language adapter modules this mutator supports.

  Mutators that work with the same AST format (e.g., BEAM languages like
  Elixir and Erlang) can declare multiple languages. Discovery will filter
  mutators based on the active language.

  ## Returns

    List of language adapter modules (e.g., `[Muex.Language.Elixir, Muex.Language.Erlang]`)
  """
  @callback supported_languages() :: [module()]

  @doc """
  Returns whether a mutation is semantically equivalent to the original code.

  Equivalent mutations can never be killed by any test and should be filtered out
  to avoid inflating the "survived" count.

  The default implementation checks for `equivalent: true` in the mutation map.
  Override this callback in your mutator for more sophisticated detection.
  """
  @callback equivalent?(mutation :: mutation()) :: boolean()

  @optional_callbacks [equivalent?: 1]

  @doc """
  Checks whether a mutation is equivalent, delegating to the mutator module.

  Falls back to checking the `:equivalent` key in the mutation map if the
  mutator does not implement `equivalent?/1`.
  """
  @spec equivalent?(mutation()) :: boolean()
  def equivalent?(%{mutator: mutator} = mutation) do
    if function_exported?(mutator, :equivalent?, 1) do
      mutator.equivalent?(mutation)
    else
      Map.get(mutation, :equivalent, false)
    end
  end

  def equivalent?(_mutation), do: false

  # Directives whose entire subtree is compile-time metadata, never a
  # runtime value. Mutating them yields invalid mutants.
  @always_skip_calls [:use, :import, :alias, :require]

  # Module attributes that carry documentation or typespecs rather than
  # runtime values. The whole attribute subtree is pruned.
  @skip_attributes [
    :doc,
    :moduledoc,
    :typedoc,
    :type,
    :typep,
    :opaque,
    :spec,
    :callback,
    :macrocallback,
    :behaviour,
    :impl,
    :derive,
    :enforce_keys
  ]

  @doc """
  Walks an AST and collects mutations from all registered mutators.

  The traversal is context-aware: it threads the nearest enclosing source
  line through `context[:line]` (so leaf mutators such as
  `Muex.Mutator.Literal` can report a real location for bare literals that
  carry no AST metadata of their own) and prunes subtrees that should never
  be mutated.

  ## Pruning rules

  The following are skipped for every mutator, regardless of configuration:

    * Module alias segments (`{:__aliases__, _, _}`), e.g. the `Phoenix`
      and `Component` atoms in `use Phoenix.Component`.
    * Directives: `use`, `import`, `alias`, `require`.
    * Documentation and typespec attributes: `@doc`, `@moduledoc`,
      `@typedoc`, `@type`, `@typep`, `@opaque`, `@spec`, `@callback`,
      `@macrocallback`, `@behaviour`, `@impl`, `@derive`, `@enforce_keys`.
    * Keyword/option keys: in a `key: value` pair only `value` is
      traversed, never the atom `key`.

  Callers can prune additional framework DSL calls by passing a list of
  call names (atoms) in `context[:skip_calls]`. For example,
  `[:attr, :slot, :scope, :pipeline]` removes Phoenix component and router
  DSL noise. See `Muex.Config` presets.

  ## Parameters

    - `ast` - The AST to traverse
    - `mutators` - List of mutator modules to apply
    - `context` - Context map. Recognised keys:
      - `:file` - source file path, copied into each mutation's location
      - `:line` - starting line (defaults to `0`); updated as the walk descends
      - `:skip_calls` - extra call names (atoms) to prune

  ## Returns

    List of all mutations found in the AST. Each mutation is augmented with
    `:original_ast` (the matched node), used later during application.
  """
  @spec walk(ast :: term(), mutators :: [module()], context :: map()) :: [mutation()]
  def walk(ast, mutators, context) do
    context = Map.put_new(context, :line, 0)
    skip_calls = Map.get(context, :skip_calls, [])
    collect(ast, mutators, context, skip_calls)
  end

  # Recursively collect mutations, threading the enclosing line and pruning
  # skipped subtrees. Preserves `Macro.prewalk/2` (pre-order) ordering while
  # adding context awareness.
  defp collect(node, mutators, context, skip_calls) do
    if skip?(node, skip_calls) do
      []
    else
      context = update_line(context, node)

      mutate_node(node, mutators, context) ++
        collect_children(node, mutators, context, skip_calls)
    end
  end

  defp mutate_node(node, mutators, context) do
    Enum.flat_map(mutators, fn mutator ->
      node
      |> mutator.mutate(context)
      |> Enum.map(&Map.put(&1, :original_ast, node))
    end)
  end

  # Call with an atom form: descend into args only. This mirrors
  # `Macro.traverse/4`, which does not visit the call name itself.
  defp collect_children({form, _meta, args}, mutators, context, skip_calls)
       when is_atom(form) do
    collect_args(args, mutators, context, skip_calls)
  end

  # Call with a non-atom form (e.g. remote call `{:., _, _}`): descend into
  # both the form and the args.
  defp collect_children({form, _meta, args}, mutators, context, skip_calls) do
    collect(form, mutators, context, skip_calls) ++
      collect_args(args, mutators, context, skip_calls)
  end

  # Two-element tuple: a keyword pair or literal pair. Never mutate an atom
  # key; always traverse the value.
  defp collect_children({left, right}, mutators, context, skip_calls) do
    left_mutations =
      if is_atom(left), do: [], else: collect(left, mutators, context, skip_calls)

    left_mutations ++ collect(right, mutators, context, skip_calls)
  end

  defp collect_children(list, mutators, context, skip_calls) when is_list(list) do
    Enum.flat_map(list, &collect(&1, mutators, context, skip_calls))
  end

  defp collect_children(_leaf, _mutators, _context, _skip_calls), do: []

  # Args may be a list (normal call) or an atom such as `nil`/`Elixir` for
  # variables and zero-arity forms, which carry no child nodes.
  defp collect_args(args, _mutators, _context, _skip_calls) when is_atom(args), do: []

  defp collect_args(args, mutators, context, skip_calls) when is_list(args) do
    Enum.flat_map(args, &collect(&1, mutators, context, skip_calls))
  end

  defp collect_args(args, mutators, context, skip_calls) do
    collect(args, mutators, context, skip_calls)
  end

  # Module alias segments: pure structural metadata.
  defp skip?({:__aliases__, _meta, _segments}, _skip_calls), do: true

  # Documentation and typespec module attributes.
  defp skip?({:@, _meta, [{attr, _attr_meta, _attr_args}]}, _skip_calls)
       when attr in @skip_attributes,
       do: true

  # Directive calls and configured DSL calls.
  defp skip?({form, _meta, args}, skip_calls)
       when is_atom(form) and (is_list(args) or is_nil(args)) do
    form in @always_skip_calls or form in skip_calls
  end

  defp skip?(_node, _skip_calls), do: false

  defp update_line(context, {_form, meta, _args}) when is_list(meta) do
    case Keyword.get(meta, :line) do
      nil -> context
      line -> Map.put(context, :line, line)
    end
  end

  defp update_line(context, _node), do: context
end
