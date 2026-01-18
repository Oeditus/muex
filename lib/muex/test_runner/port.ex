defmodule Muex.TestRunner.Port do
  @moduledoc """
  Runs tests in isolated Erlang port processes.

  Each test run executes in a separate BEAM VM via port, providing complete isolation
  between mutations and preventing hot-swapping conflicts.
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
    - `mutated_file` - Path to the mutated source file (will be compiled in the test env)
    - `opts` - Options:
      - `:timeout_ms` - Test timeout in milliseconds (default: 5000)
      - `:mix_env` - Mix environment (default: "test")

  ## Returns

    `{:ok, test_result}` or `{:error, reason}`
  """
  @spec run_tests([Path.t()], Path.t() | nil, keyword()) ::
          {:ok, test_result()} | {:error, term()}
  def run_tests(test_files, mutated_file \\ nil, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 5000)
    mix_env = Keyword.get(opts, :mix_env, "test")
    start_time = System.monotonic_time(:millisecond)

    result =
      case spawn_test_port(test_files, mutated_file, mix_env, timeout_ms) do
        {:ok, output, exit_code} ->
          duration_ms = System.monotonic_time(:millisecond) - start_time
          failures = count_failures(output)

          {:ok,
           %{failures: failures, output: output, exit_code: exit_code, duration_ms: duration_ms}}

        {:error, reason} ->
          {:error, reason}
      end

    result
  end

  defp spawn_test_port(test_files, mutated_file, mix_env, timeout_ms) do
    args =
      if mutated_file do
        test_args = test_files
        ["do", "compile", "--force", ",", "test" | test_args]
      else
        ["test"] ++ test_files
      end

    current_env =
      System.get_env()
      |> Enum.map(fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    env =
      Enum.reject(current_env, fn {k, _v} -> k == ~c"MIX_ENV" end) ++
        [{~c"MIX_ENV", String.to_charlist(mix_env)}]

    cmd_args = Enum.map(args, &String.to_charlist/1)
    port_opts = [:binary, :exit_status, :stderr_to_stdout, :hide, env: env, args: cmd_args]

    try do
      mix_path = System.find_executable("mix")
      port = Port.open({:spawn_executable, mix_path}, port_opts)
      collect_output(port, "", timeout_ms)
    rescue
      e -> {:error, e}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

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
        safe_close(port)
        {:error, :timeout}
    end
  rescue
    e -> {:error, e}
  end

  defp safe_close(port) do
    Port.close(port)
  rescue
    ArgumentError -> :ok
  catch
    :error, :badarg -> :ok
  end

  defp count_failures(output) do
    case Regex.run(~r/(\d+) failures?/, output) do
      [_, count] ->
        String.to_integer(count)

      nil ->
        if String.contains?(output, "0 failures") do
          0
        else
          1
        end
    end
  end
end
