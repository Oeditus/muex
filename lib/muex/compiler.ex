defmodule Muex.Compiler do
  @moduledoc """
  Compiles mutated ASTs and manages module hot-swapping.

  Uses the language adapter for converting AST to source and compiling modules.
  """
  @doc """
  Compiles a mutated AST and loads it into the BEAM.

  ## Parameters

    - `mutation` - The mutation map containing the mutated AST
    - `original_ast` - The original (complete) AST with mutation applied
    - `module_name` - The module name to compile
    - `language_adapter` - The language adapter module

  ## Returns

    - `{:ok, {module, original_binary}}` - Successfully compiled and loaded module with original binary
    - `{:error, reason}` - Compilation failed
  """
  @spec compile(map(), term(), atom(), module()) :: {:ok, {module(), binary()}} | {:error, term()}
  def compile(mutation, original_ast, module_name, language_adapter) do
    original_binary = get_module_binary(module_name)
    mutated_full_ast = apply_mutation(original_ast, mutation)

    with {:ok, source} <- language_adapter.unparse(mutated_full_ast),
         {:ok, module} <- compile_and_load(source, module_name) do
      {:ok, {module, original_binary}}
    end
  end

  @doc """
  Compiles a mutated AST and writes it to a temporary file.

  This is used for port-based test execution where the mutated source
  needs to be on disk for a separate BEAM VM to compile.

  ## Parameters

    - `mutation` - The mutation map containing the mutated AST
    - `file_entry` - The file entry containing the original AST and path
    - `language_adapter` - The language adapter module

  ## Returns

    - `{:ok, temp_file_path}` - Successfully wrote mutated source to temp file
    - `{:error, reason}` - Failed to write mutated source
  """
  @spec compile_to_file(map(), map(), module()) :: {:ok, Path.t()} | {:error, term()}
  def compile_to_file(mutation, file_entry, language_adapter) do
    mutated_full_ast = apply_mutation(file_entry.ast, mutation)

    with {:ok, source} <- language_adapter.unparse(mutated_full_ast) do
      write_to_temp_file(source, file_entry.path)
    end
  end

  @doc """
  Generates the mutated source code string without writing to disk.

  This is preferred over `compile_to_file/3` when the caller only needs the
  source string (e.g. to write into a sandbox).

  ## Returns

    - `{:ok, source_string}` - The mutated source code
    - `{:error, reason}` - AST-to-source conversion failed
  """
  @spec compile_to_source(map(), map(), module()) :: {:ok, String.t()} | {:error, term()}
  def compile_to_source(mutation, file_entry, language_adapter) do
    mutated_full_ast = apply_mutation(file_entry.ast, mutation)
    language_adapter.unparse(mutated_full_ast)
  end

  @doc """
  Restores the original module from its binary.

  ## Parameters

    - `module_name` - The module to restore
    - `original_binary` - The original module binary

  ## Returns

    - `:ok` - Successfully restored
    - `{:error, reason}` - Restoration failed
  """
  @spec restore(atom(), binary()) :: :ok | {:error, term()}
  def restore(module_name, original_binary) do
    :code.purge(module_name)
    :code.delete(module_name)

    case :code.load_binary(module_name, ~c"nofile", original_binary) do
      {:module, ^module_name} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, e}
  end

  defp write_to_temp_file(source, original_path) do
    dir = Path.dirname(original_path)
    basename = Path.basename(original_path, Path.extname(original_path))
    timestamp = System.system_time(:microsecond)
    temp_file = Path.join(dir, "#{basename}_mutated_#{timestamp}#{Path.extname(original_path)}")

    case File.write(temp_file, source) do
      :ok -> {:ok, temp_file}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, e}
  end

  defp get_module_binary(module_name) do
    case :code.get_object_code(module_name) do
      {^module_name, binary, _filename} -> binary
      :error -> nil
    end
  end

  defp compile_and_load(source, module_name) do
    :code.purge(module_name)
    :code.delete(module_name)
    [{^module_name, binary}] = Code.compile_string(source)

    case :code.load_binary(module_name, ~c"nofile", binary) do
      {:module, ^module_name} -> {:ok, module_name}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, e}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp apply_mutation(ast, mutation) do
    original_ast = Map.get(mutation, :original_ast)
    mutated_ast = Map.get(mutation, :ast)
    target_line = get_in(mutation, [:location, :line])

    transform(ast, 0, original_ast, mutated_ast, target_line)
  end

  # Walk the AST while tracking the nearest enclosing source line, replacing
  # the node that structurally matches the mutation's original node on the
  # target line. Tracking the enclosing line is essential for bare literals
  # (atoms, numbers, strings), which carry no metadata of their own: their
  # location is the line of the surrounding expression, mirroring how
  # `Muex.Mutator.walk/3` assigns it during generation. Keyword keys and
  # module alias segments are left untouched, matching the generation-time
  # pruning so application targets exactly the nodes that were considered.
  defp transform(node, enclosing_line, original, mutated, target_line) do
    line = node_line(node, enclosing_line)

    cond do
      line == target_line and structurally_equal?(node, original) ->
        mutated

      match?({:__aliases__, _meta, _segments}, node) ->
        node

      true ->
        transform_children(node, line, original, mutated, target_line)
    end
  end

  # Call with an atom form: keep the form and recurse into args only.
  defp transform_children({form, meta, args}, line, original, mutated, target_line)
       when is_atom(form) do
    {form, meta, transform_args(args, line, original, mutated, target_line)}
  end

  # Call with a non-atom form (e.g. remote call): recurse into form and args.
  defp transform_children({form, meta, args}, line, original, mutated, target_line) do
    new_form = transform(form, line, original, mutated, target_line)
    {new_form, meta, transform_args(args, line, original, mutated, target_line)}
  end

  # Two-element tuple: never rewrite an atom key, always recurse the value.
  defp transform_children({left, right}, line, original, mutated, target_line) do
    new_left =
      if is_atom(left), do: left, else: transform(left, line, original, mutated, target_line)

    {new_left, transform(right, line, original, mutated, target_line)}
  end

  defp transform_children(list, line, original, mutated, target_line) when is_list(list) do
    Enum.map(list, &transform(&1, line, original, mutated, target_line))
  end

  defp transform_children(leaf, _line, _original, _mutated, _target_line), do: leaf

  defp transform_args(args, _line, _original, _mutated, _target_line) when is_atom(args) do
    args
  end

  defp transform_args(args, line, original, mutated, target_line) when is_list(args) do
    Enum.map(args, &transform(&1, line, original, mutated, target_line))
  end

  defp transform_args(args, line, original, mutated, target_line) do
    transform(args, line, original, mutated, target_line)
  end

  defp node_line({_form, meta, _args}, enclosing_line) when is_list(meta) do
    Keyword.get(meta, :line, enclosing_line)
  end

  defp node_line(_node, enclosing_line) do
    enclosing_line
  end

  defp structurally_equal?({form1, _meta1, args1}, {form2, _meta2, args2}) do
    form1 == form2 && args_equal?(args1, args2)
  end

  defp structurally_equal?(val1, val2) do
    val1 == val2
  end

  defp args_equal?(nil, nil) do
    true
  end

  defp args_equal?([], []) do
    true
  end

  defp args_equal?([h1 | t1], [h2 | t2]) do
    structurally_equal?(h1, h2) && args_equal?(t1, t2)
  end

  defp args_equal?(_, _) do
    false
  end
end
