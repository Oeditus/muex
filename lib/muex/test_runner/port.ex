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
          tests_run: non_neg_integer() | nil,
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
      - `:exclude_all` - Exclude every test (`--exclude test`), so the run
        compiles the project and loads the test files but runs nothing
        (default: false).

  ## Returns

    `{:ok, test_result}` or `{:error, reason}`
  """
  @spec run_tests([Path.t()], keyword()) :: {:ok, test_result()} | {:error, term()}
  def run_tests(test_files, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 5000)
    mix_env = Keyword.get(opts, :mix_env, "test")
    cd = Keyword.get(opts, :cd)
    no_compile = Keyword.get(opts, :no_compile, false)
    exclude_flags = if Keyword.get(opts, :exclude_all, false), do: ["--exclude", "test"], else: []
    start_time = System.monotonic_time(:millisecond)

    case spawn_test_port(test_files, mix_env, timeout_ms, cd, no_compile, exclude_flags) do
      {:ok, output, exit_code} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time

        cond do
          exit_code != 0 and compile_error?(output) ->
            {:error, {:compile_error, output}}

          not has_exunit_summary?(output) ->
            # The suite produced no summary we can recognise, so we do not know
            # whether the mutant was detected. Inventing a failure count here
            # would turn "unmeasured" into a definite verdict; callers classify
            # `{:error, _}` as :invalid instead.
            {:error, {:no_test_summary, output}}

          true ->
            {:ok,
             output
             |> summary_counts(exit_code)
             |> Map.merge(%{output: output, exit_code: exit_code, duration_ms: duration_ms})}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp spawn_test_port(test_files, mix_env, timeout_ms, cd, no_compile, exclude_flags) do
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
    args = ["test", "--max-failures", "1"] ++ compile_flags ++ exclude_flags ++ test_files

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
  @compile_error_pattern ~r/\*\* \([\w.]*(?:Error|Missing[\w.]*)\)/
  defp compile_error?(output) do
    not has_exunit_summary?(output) and
      Regex.match?(@compile_error_pattern, output)
  end

  # Elixir < 1.20 prints "5 tests, 2 failures"; Elixir >= 1.20 prints a
  # "Result: ..." line ("Result: 1 passed", "Result: 0/2 passed",
  # "Result: 0 tests, 1 excluded") and the word "failures" nowhere at all.
  # Both generations must be recognised.
  @pre_120_summary_pattern ~r/\d+ tests?, \d+ failures?/
  @post_120_summary_pattern ~r/^Result: /m

  defp has_exunit_summary?(output) do
    Regex.match?(@pre_120_summary_pattern, output) or
      String.contains?(output, "0 failures") or
      Regex.match?(@post_120_summary_pattern, output)
  end

  # Elixir < 1.20 carries the count in the summary line itself
  # ("5 tests, 2 failures"); Elixir >= 1.20 puts it on its own "Failed: N test(s)"
  # line and omits the line entirely when nothing failed. An umbrella prints one
  # summary per app, so every match counts, not only the first.
  @pre_120_failures_pattern ~r/^(?:\d+ \w+, )*(\d+) failures?/m
  @post_120_failures_pattern ~r/^Failed: (\d+) tests?/m

  @ansi_escape ~r/\e\[[0-9;]*m/

  @doc false
  # The failure count and the number of tests that ran, read from every summary
  # in the output. ANSI colours come off first: a suite that forces ExUnit's
  # colours on wraps the pre-1.20 summary line in escape codes, which the
  # line-anchored patterns would otherwise miss.
  @spec summary_counts(String.t(), integer()) :: %{
          failures: non_neg_integer(),
          tests_run: non_neg_integer() | nil
        }
  def summary_counts(output, exit_code) do
    plain = String.replace(output, @ansi_escape, "")
    %{failures: count_failures(plain, exit_code), tests_run: tests_run(plain)}
  end

  # Only reached for output that carries a recognisable ExUnit summary; an
  # unrecognisable run is rejected as {:error, {:no_test_summary, _}} upstream.
  #
  # A non-zero exit with no failure counted is still a failure. A setup_all
  # crash reports its tests as invalid, not failed: "Result: 0 tests, 1 invalid"
  # on 1.20, "1 test, 0 failures, 1 invalid" before it, and exits non-zero either
  # way. Reading that as a clean pass, or as "nothing ran", would hide a mutant
  # that broke the test setup.
  defp count_failures(output, exit_code) do
    counted =
      sum_matches(@pre_120_failures_pattern, output) ||
        sum_matches(@post_120_failures_pattern, output)

    cond do
      is_integer(counted) and counted > 0 -> counted
      exit_code != 0 -> 1
      true -> 0
    end
  end

  defp sum_matches(pattern, output) do
    case Regex.scan(pattern, output, capture: :all_but_first) do
      [] -> nil
      matches -> matches |> List.flatten() |> Enum.map(&String.to_integer/1) |> Enum.sum()
    end
  end

  # Elixir >= 1.20 counts only the tests that passed or failed: "Result: 0 tests",
  # "Result: 3 passed", "Result: 1/2 passed (...)", with any excluded, skipped or
  # invalid tests listed after that. Elixir < 1.20 counts every test, excluded,
  # skipped and invalid ones included, and lists those after the failures:
  # "3 tests, 0 failures, 3 excluded", or "1 doctest, 2 tests, 0 failures, 1 skipped".
  @post_120_run_pattern ~r/^Result: (?:(0) tests|(\d+) passed|\d+\/(\d+) passed)/m
  @pre_120_run_pattern ~r/^((?:\d+ \w+, )*)\d+ failures?((?:, \d+ \w+)*)/m

  @doc false
  # How many tests actually ran, summed over every summary in the output (an
  # umbrella prints one per app). A mutant whose chosen tests were all excluded,
  # skipped or invalid was never tested, so it must not be reported as having
  # survived them. nil when the output carries no count this can read.
  @spec tests_run(String.t()) :: non_neg_integer() | nil
  def tests_run(output) do
    case Regex.scan(@post_120_run_pattern, output, capture: :all_but_first) do
      [] -> pre_120_tests_run(output)
      summaries -> summaries |> Enum.map(&first_count/1) |> Enum.sum()
    end
  end

  defp pre_120_tests_run(output) do
    case Regex.scan(@pre_120_run_pattern, output, capture: :all_but_first) do
      [] ->
        nil

      summaries ->
        summaries
        |> Enum.map(fn [counted | not_run] ->
          max(sum_counts(counted) - sum_counts(Enum.join(not_run)), 0)
        end)
        |> Enum.sum()
    end
  end

  defp first_count(groups), do: groups |> Enum.find(&(&1 != "")) |> String.to_integer()

  defp sum_counts(text) do
    ~r/\d+/
    |> Regex.scan(text)
    |> List.flatten()
    |> Enum.map(&String.to_integer/1)
    |> Enum.sum()
  end

  @project_header ~r/^==> (\S+)$/
  # Three attributes, not a list of three: OTP 28 regexes hold a reference,
  # and only a bare regex attribute can be injected into a function body.
  # "== Compilation error in file lib/b.ex =="
  @compilation_error_file ~r/^== Compilation error in file (\S+) ==$/
  # "** (CompileError) lib/b.ex: cannot compile module B", "** (SyntaxError)
  # lib/b.ex:3:1: ..." (1.15), "** (TokenMissingError) token missing on lib/b.ex:2:15:"
  @exception_file ~r/^\*\* \([\w.]+\) (?:.*? on )?(\S+?\.exs?):/
  # the pointer under each diagnostic: "└─ lib/b.ex:3:1", "└─ lib/b.ex: B.f/1"
  @diagnostic_file ~r/^\s*└─ (\S+?\.exs?)(?::|$)/u
  # the same on Elixir 1.15, an indented line: "  lib/b.ex:3", "  lib/a.ex:3: A.add/2"
  @plain_diagnostic_file ~r/^\s+(\S+?\.exs?):\d+(?::\d+)?(?::|$)/
  # "    error: undefined function ...", "warning: variable "b" is unused ..."
  @diagnostic_kind ~r/^\s*(error|warning): /
  @warnings_failed "Compilation failed due to warnings"

  @doc false
  # Each file a failed compile names as a cause, with the Mix project it was
  # compiled in: the last "==> app" header before it, which an umbrella prints
  # for each app and a plain project only for its dependencies (so nil, or a
  # dependency's name, for the project's own files). Paths are as the compiler
  # printed them, relative to that project. The file is named on the
  # "== Compilation error in file" line, on the "** (SomeError)" line, and under
  # each diagnostic. A warning's file counts only when warnings are what failed
  # the build (--warnings-as-errors): a warning printed beside an error in
  # another file is not its cause. A diagnostic ends at its pointer, or at the
  # next "==" or "**" line, so the stack trace after it is not read as one.
  @spec error_files(String.t()) :: [{String.t() | nil, String.t()}]
  def error_files(output) do
    plain = String.replace(output, @ansi_escape, "")
    warnings_fail? = String.contains?(plain, @warnings_failed)

    {_project, _kind, files} =
      plain
      |> String.split("\n")
      |> Enum.reduce({nil, nil, []}, fn line, {project, kind, files} ->
        case {Regex.run(@project_header, line, capture: :all_but_first),
              Regex.run(@diagnostic_kind, line, capture: :all_but_first)} do
          {[name], _} ->
            {name, nil, files}

          {nil, [new_kind]} ->
            {project, new_kind, files}

          {nil, nil} ->
            counts? = kind == "error" or (kind == "warning" and warnings_fail?)

            pointer =
              if counts?, do: matches([@diagnostic_file, @plain_diagnostic_file], line), else: []

            paths = matches([@compilation_error_file, @exception_file], line) ++ pointer
            ended? = pointer != [] or String.starts_with?(line, ["== ", "** ("])

            {project, if(ended?, do: nil, else: kind),
             Enum.reverse(Enum.map(paths, &{project, &1}), files)}
        end
      end)

    files |> Enum.reverse() |> Enum.uniq()
  end

  defp matches(patterns, line) do
    Enum.flat_map(patterns, &(Regex.run(&1, line, capture: :all_but_first) || []))
  end

  @doc false
  # Whether the output shows a failed compile, as opposed to a run that got past
  # compiling and then stopped before ExUnit reported.
  @spec compile_failed?(String.t()) :: boolean()
  def compile_failed?(output) do
    String.contains?(output, "== Compilation error in file") or
      String.contains?(output, @warnings_failed)
  end
end
