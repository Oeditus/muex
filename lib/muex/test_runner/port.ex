defmodule Muex.TestRunner.Port do
  @moduledoc """
  Runs tests in isolated Erlang port processes.

  Each test run executes in a separate BEAM VM via port, providing complete isolation
  between mutations and preventing hot-swapping conflicts.

  The worker pool deletes the .beam file for the mutated module before calling this
  runner. `mix test` performs incremental compilation automatically, so only the
  single mutated file is recompiled — no `compile --force` needed. This is critical
  for umbrella projects where a forced recompile takes minutes per mutation.
  """
  @type test_result :: %{
          failures: non_neg_integer(),
          output: String.t(),
          exit_code: non_neg_integer(),
          duration_ms: non_neg_integer()
        }
  @doc """
  Runs tests in an isolated port process.

  ## Parameters

    - `test_files` - List of test file paths to execute
    - `opts` - Options:
      - `:timeout_ms` - Test timeout in milliseconds (default: 5000)
      - `:mix_env` - Mix environment (default: "test")
      - `:cd` - Working directory for the port process (default: current dir).
        When running inside a sandbox, this should be the sandbox root.

  ## Returns

    `{:ok, test_result}` or `{:error, reason}`
  """
  @spec run_tests([Path.t()], keyword()) :: {:ok, test_result()} | {:error, term()}
  def run_tests(test_files, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 5000)
    mix_env = Keyword.get(opts, :mix_env, "test")
    cd = Keyword.get(opts, :cd)
    no_compile = Keyword.get(opts, :no_compile, false)
    start_time = System.monotonic_time(:millisecond)

    case spawn_test_port(test_files, mix_env, timeout_ms, cd, no_compile) do
      {:ok, output, exit_code} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time

        if exit_code != 0 and compile_error?(output) do
          {:error, {:compile_error, output}}
        else
          failures = count_failures(output, exit_code)

          {:ok,
           %{failures: failures, output: output, exit_code: exit_code, duration_ms: duration_ms}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp spawn_test_port(test_files, mix_env, timeout_ms, cd, no_compile) do
    # When the caller pre-compiled the mutated module and wrote the .beam
    # directly, we pass --no-compile to skip Mix's compilation phase entirely.
    # We also always pass --no-deps-check and --no-archives-check since deps
    # don't change between mutations.
    compile_flags =
      if no_compile do
        ["--no-compile", "--no-deps-check", "--no-archives-check"]
      else
        ["--no-deps-check", "--no-archives-check"]
      end

    mix_path = System.find_executable("mix")
    # --max-failures 1: a mutant is killed by any failing test, so stop at the
    # first one instead of running the whole (selected) suite.
    args = ["test", "--max-failures", "1"] ++ compile_flags ++ test_files

    current_env =
      System.get_env()
      |> Enum.map(fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    env =
      Enum.reject(current_env, fn {k, _v} -> k == ~c"MIX_ENV" end) ++
        [{~c"MIX_ENV", String.to_charlist(mix_env)}]

    cmd_args = Enum.map(args, &String.to_charlist/1)

    port_opts =
      [:binary, :exit_status, :stderr_to_stdout, :hide, env: env, args: cmd_args]
      |> maybe_add_cd(cd)

    try do
      port = Port.open({:spawn_executable, mix_path}, port_opts)
      collect_output(port, "", timeout_ms)
    rescue
      e -> {:error, e}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  defp maybe_add_cd(port_opts, nil), do: port_opts
  defp maybe_add_cd(port_opts, cd), do: [{:cd, String.to_charlist(cd)} | port_opts]

  defp collect_output(port, acc, timeout_ms) do
    receive do
      {^port, {:data, data}} when is_binary(data) ->
        collect_output(port, acc <> data, timeout_ms)

      {^port, {:exit_status, exit_code}} ->
        safe_close(port)
        {:ok, acc, exit_code}

      _msg ->
        collect_output(port, acc, timeout_ms)
    after
      timeout_ms ->
        kill_os_process(port)
        safe_close(port)
        {:error, :timeout}
    end
  rescue
    e -> {:error, e}
  end

  # Kill the OS process and its entire process tree. `mix test` spawns a
  # child beam.smp process; killing only the parent leaves the child orphaned.
  # We walk the child-process tree (via `pkill -P`) before killing the root.
  defp kill_os_process(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} ->
        kill_process_tree(os_pid)

      nil ->
        :ok
    end
  rescue
    _ -> :ok
  end

  # Recursively kill all descendants of `pid`, then kill `pid` itself.
  defp kill_process_tree(pid) do
    # Find direct children
    {children_str, _} = System.cmd("pgrep", ["-P", "#{pid}"], stderr_to_stdout: true)

    child_pids =
      children_str
      |> String.split("\n", trim: true)
      |> Enum.flat_map(fn s ->
        case Integer.parse(s) do
          {n, _} -> [n]
          :error -> []
        end
      end)

    # Kill children first (depth-first)
    Enum.each(child_pids, &kill_process_tree/1)

    # Now kill this process
    System.cmd("kill", ["-9", "#{pid}"], stderr_to_stdout: true)
  rescue
    _ -> :ok
  end

  defp safe_close(port) do
    Port.close(port)
  rescue
    ArgumentError -> :ok
  catch
    :error, :badarg -> :ok
  end

  # Detect whether mix test output indicates a compilation error rather than
  # a test failure. When a mutation breaks compilation, mix test exits non-zero
  # but never runs any tests — these should be classified as :invalid, not :killed.
  #
  # The key signal is: non-zero exit with no ExUnit summary in the output.
  # We also check for Elixir exception patterns (CompileError, SyntaxError,
  # TokenMissingError, etc.) to avoid false positives from other non-test crashes.
  @compile_error_pattern ~r/\*\* \(\w*(?:Error|Missing\w*)\)/
  defp compile_error?(output) do
    not has_exunit_summary?(output) and
      Regex.match?(@compile_error_pattern, output)
  end

  defp has_exunit_summary?(output) do
    Regex.match?(~r/\d+ tests?, \d+ failures?/, output) or
      String.contains?(output, "0 failures")
  end

  defp count_failures(output, _exit_code) do
    # Always try to parse the actual failure count from output for reporting
    # accuracy. Fall back to 1 only when parsing fails (e.g. no recognizable
    # ExUnit summary because something crashed).
    case Regex.run(~r/(\d+) failures?/, output) do
      [_, count] ->
        String.to_integer(count)

      nil ->
        if String.contains?(output, "0 failures") do
          0
        else
          # No ExUnit output at all — something crashed. Treat as killed.
          1
        end
    end
  end
end
