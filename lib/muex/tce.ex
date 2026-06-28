defmodule Muex.Tce do
  @moduledoc """
  Trivial Compiler Equivalence (TCE) for mutants.

  Two pieces of source are *compiler-equivalent* when they compile to the same
  BEAM code. Such a mutant can never be killed — no test can distinguish it from
  the original — so it is an equivalent mutant and should be dropped.

  This catches cases the AST-pattern rules in `Muex.Equivalence` cannot, e.g.
  deleting a `@moduledoc`/`@doc` or any change that the compiler erases, where
  the resulting function bytecode is byte-for-byte identical.

  The comparison is **sound**: both modules are compiled under the same
  throwaway name, disassembled, their line annotations stripped, and the
  remaining instruction streams compared. Equivalence is reported only on an
  exact match; anything that fails to compile is treated as *not* provably
  equivalent so a real mutant is never hidden.
  """

  @doc """
  Returns true when the two quoted modules compile to identical BEAM code.

  Returns false if they differ or if either fails to compile.
  """
  @spec equivalent?(Macro.t(), Macro.t()) :: boolean()
  def equivalent?(module_ast_a, module_ast_b) do
    # A mutation that changes the module's *name* is observable (callers can no
    # longer find it), so it must never be called equivalent. Because we
    # compile both sides under a shared throwaway name to compare bytecode, that
    # rename would otherwise mask a name change — so guard against it up front.
    if same_module_name?(module_ast_a, module_ast_b) do
      # Both sides MUST compile under the *same* throwaway name: BEAM derives a
      # closure's identity hash from the module name, so different names would
      # make even identical code fingerprint differently. The name is unique
      # per call, so concurrent comparisons don't collide.
      probe = probe_alias()

      case {fingerprint(module_ast_a, probe), fingerprint(module_ast_b, probe)} do
        {{:ok, a}, {:ok, b}} -> a == b
        _ -> false
      end
    else
      false
    end
  end

  defp same_module_name?({:defmodule, _, [alias_a, _]}, {:defmodule, _, [alias_b, _]}) do
    alias_segments(alias_a) == alias_segments(alias_b)
  end

  defp same_module_name?(_a, _b), do: false

  defp alias_segments({:__aliases__, _meta, segments}), do: segments
  defp alias_segments(other), do: other

  @doc """
  Like `equivalent?/2`, but the mutant is supplied as source text (as produced
  by the compiler when applying a mutation). Returns false if it does not parse.
  """
  @spec equivalent_source?(Macro.t(), String.t()) :: boolean()
  def equivalent_source?(original_module_ast, mutated_source) when is_binary(mutated_source) do
    case Code.string_to_quoted(mutated_source) do
      {:ok, mutant_ast} -> equivalent?(original_module_ast, mutant_ast)
      _ -> false
    end
  end

  # Compile under a throwaway name, disassemble, and strip line annotations so
  # only the behavioural instruction stream remains. The module name is shared
  # by both sides of a comparison, so it needs no further normalisation.
  defp fingerprint(module_ast, probe) do
    with {:ok, binary} <- compile_binary(module_ast, probe) do
      {:beam_file, _module, _exports, _attrs, _compile_info, code} = :beam_disasm.file(binary)
      {:ok, strip_lines(code)}
    end
  end

  defp compile_binary(module_ast, probe) do
    # Only a single top-level `defmodule` can be safely renamed to a throwaway
    # name. Anything else (multiple modules, bare expressions) is refused so we
    # never compile and clobber the project's real modules mid-run.
    case rename_module(module_ast, probe) do
      {:ok, renamed} ->
        # with_diagnostics captures ordinary compiler warnings (e.g. an unused
        # variable introduced by a mutation) instead of printing them, keeping
        # mutant compile noise off the console.
        {result, _diagnostics} = Code.with_diagnostics(fn -> compile_renamed(renamed) end)
        result

      :error ->
        :error
    end
  end

  defp compile_renamed(renamed) do
    case compile_without_verification(renamed) do
      [{module, binary} | _] ->
        purge(module)
        {:ok, binary}

      _ ->
        :error
    end
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  # Compile the throwaway probe and return `[{module, binary}]`, deliberately
  # WITHOUT running the post-compile verification pass.
  #
  # `Code.compile_quoted/1` is `Module.ParallelChecker.verify(fn ->
  # :elixir_compiler.quoted(...) end)`: after compiling, it runs the module
  # through `Module.ParallelChecker`, which invokes every `@after_verify`
  # callback the module registered. For a Spark/Ash module (`Ash.Resource`,
  # `Ash.Domain`, ...) that callback is `__verify_spark_dsl__/1`, which — once
  # the module has been renamed to a throwaway name — warns that the name isn't
  # a configured `:ash_domains` entry and raises (Spark catches it and re-emits
  # it as a warning) because the renamed module no longer owns its resources.
  # The checker prints those warnings UNCONDITIONALLY straight to the group
  # leader, so the surrounding `Code.with_diagnostics/2` cannot swallow them and
  # they flood the output for every resource module on every mutant.
  #
  # TCE only needs the compiled function bytecode, and verification never
  # influences it (a module compiles to byte-identical BEAM whether or not its
  # `@after_verify` hooks run), so skipping verification is both sound and
  # strictly cheaper. See https://github.com/Oeditus/muex/issues/17.
  #
  # This mirrors `verify/1`'s own setup (seed `:elixir_checker_info`, restore it
  # afterwards) but stops the lazily-created checker cache instead of running it.
  # If a future Elixir drops the internals we rely on, we fall back to the
  # ordinary (verifying) compile so TCE keeps working.
  defp compile_without_verification(quoted) do
    if function_exported?(:elixir_compiler, :quoted, 3) and
         function_exported?(Module.ParallelChecker, :stop, 1) do
      previous = :erlang.put(:elixir_checker_info, {self(), nil})

      try do
        result = :elixir_compiler.quoted(quoted, "nofile", fn _file, _module -> :ok end)

        case :erlang.get(:elixir_checker_info) do
          {_pid, nil} -> :ok
          {_pid, cache} -> Module.ParallelChecker.stop(cache)
        end

        result
      after
        if previous == :undefined do
          :erlang.erase(:elixir_checker_info)
        else
          :erlang.put(:elixir_checker_info, previous)
        end
      end
    else
      Code.compile_quoted(quoted)
    end
  end

  defp probe_alias do
    segment = String.to_atom("MuexTceProbe#{System.unique_integer([:positive])}")
    {:__aliases__, [], [segment]}
  end

  defp rename_module({:defmodule, meta, [_alias, body]}, probe) do
    {:ok, {:defmodule, meta, [probe, body]}}
  end

  defp rename_module(_other, _probe), do: :error

  defp purge(module) do
    :code.purge(module)
    :code.delete(module)
  end

  defp strip_lines(list) when is_list(list) do
    list
    |> Enum.reject(&match?({:line, _}, &1))
    |> Enum.map(&strip_lines/1)
  end

  defp strip_lines(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> strip_lines() |> List.to_tuple()
  end

  defp strip_lines(other), do: other
end
