defmodule Muex.WorkerPool do
  @moduledoc """
  Manages a pool of workers for parallel mutation testing.

  Uses GenServer to coordinate mutation testing across a configurable number
  of workers, preventing system overload while maximizing throughput.
  """
  use GenServer
  require Logger
  @default_max_workers 4
  defmodule State do
    @moduledoc false
    defstruct [
      :max_workers,
      :pending_mutations,
      :active_workers,
      :results,
      :file_entry,
      :language_adapter,
      :opts,
      :dependency_map,
      :file_to_module,
      :caller,
      :total_mutations,
      :completed_mutations
    ]
  end

  @doc """
  Starts the worker pool.

  ## Parameters

    - `opts` - Options:
      - `:max_workers` - Maximum concurrent workers (default: 4)
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Runs mutations through the worker pool.

  ## Parameters

    - `pool` - The worker pool PID
    - `mutations` - List of mutations to test
    - `file_entry` - The file entry containing the original AST
    - `language_adapter` - The language adapter module
    - `dependency_map` - Map of modules to test files
    - `file_to_module` - Map of file paths to module names
    - `opts` - Options including `:timeout_ms`

  ## Returns

    List of mutation results
  """
  @spec run_mutations(
          pid(),
          [map()],
          map(),
          module(),
          map(),
          map(),
          keyword()
        ) :: [map()]
  def run_mutations(
        pool,
        mutations,
        file_entry,
        language_adapter,
        dependency_map,
        file_to_module,
        opts \\ []
      ) do
    GenServer.call(
      pool,
      {:run_mutations, mutations, file_entry, language_adapter, dependency_map, file_to_module,
       opts},
      :infinity
    )
  end

  @impl true
  def init(opts) do
    max_workers = Keyword.get(opts, :max_workers, @default_max_workers)

    state = %State{
      max_workers: max_workers,
      pending_mutations: :queue.new(),
      active_workers: %{},
      results: [],
      file_entry: nil,
      language_adapter: nil,
      opts: [],
      dependency_map: %{},
      file_to_module: %{},
      caller: nil,
      total_mutations: 0,
      completed_mutations: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call(
        {:run_mutations, mutations, file_entry, language_adapter, dependency_map, file_to_module,
         opts},
        from,
        state
      ) do
    pending_queue =
      Enum.reduce(mutations, :queue.new(), fn mutation, queue -> :queue.in(mutation, queue) end)

    new_state = %{
      state
      | pending_mutations: pending_queue,
        file_entry: file_entry,
        language_adapter: language_adapter,
        dependency_map: dependency_map,
        file_to_module: file_to_module,
        opts: opts,
        caller: from,
        results: [],
        total_mutations: length(mutations),
        completed_mutations: 0
    }

    if Enum.empty?(mutations) do
      {:reply, [], new_state}
    else
      updated_state = start_workers(new_state)
      {:noreply, updated_state}
    end
  end

  @impl true
  def handle_info({:worker_done, worker_ref, result}, state) do
    {_worker_pid, new_active} = Map.pop(state.active_workers, worker_ref)
    new_results = [result | state.results]
    new_completed = state.completed_mutations + 1

    # Print progress dot (only if Reporter module is available)
    try do
      Muex.Reporter.print_progress(result, new_completed, state.total_mutations)
    rescue
      UndefinedFunctionError -> :ok
    end

    new_state = %{
      state
      | active_workers: new_active,
        results: new_results,
        completed_mutations: new_completed
    }

    final_state =
      if :queue.is_empty(new_state.pending_mutations) and map_size(new_state.active_workers) == 0 do
        GenServer.reply(new_state.caller, Enum.reverse(new_state.results))
        %{new_state | caller: nil}
      else
        start_workers(new_state)
      end

    {:noreply, final_state}
  end

  defp start_workers(state) do
    available_slots = state.max_workers - map_size(state.active_workers)

    if available_slots > 0 and not :queue.is_empty(state.pending_mutations) do
      start_worker(state)
    else
      state
    end
  end

  defp start_worker(state) do
    case :queue.out(state.pending_mutations) do
      {{:value, mutation}, new_queue} ->
        parent = self()
        task_ref = make_ref()

        _pid =
          spawn(fn ->
            result =
              run_mutation_worker(
                mutation,
                state.file_entry,
                state.language_adapter,
                state.dependency_map,
                state.file_to_module,
                state.opts
              )

            send(parent, {:worker_done, task_ref, result})
          end)

        new_active = Map.put(state.active_workers, task_ref, mutation)
        new_state = %{state | pending_mutations: new_queue, active_workers: new_active}
        start_workers(new_state)

      {:empty, _queue} ->
        state
    end
  end

  defp run_mutation_worker(
         mutation,
         file_entry,
         language_adapter,
         dependency_map,
         file_to_module,
         opts
       ) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 5000)
    start_time = System.monotonic_time(:millisecond)

    test_files =
      Muex.DependencyAnalyzer.get_tests_for_mutation(
        mutation,
        dependency_map,
        file_to_module
      )

    test_files =
      if match?([], test_files) do
        Path.wildcard("test/**/*_test.exs")
      else
        test_files
      end

    result =
      case Muex.Compiler.compile_to_file(mutation, file_entry, language_adapter) do
        {:ok, mutated_file} ->
          {:ok, mutated_source} = File.read(mutated_file)
          original_file = file_entry.path
          {:ok, original_source} = File.read(original_file)
          backup_file = original_file <> ".backup"
          File.write!(backup_file, original_source)
          File.write!(original_file, mutated_source)
          File.rm!(mutated_file)
          module_name = file_entry.module_name

          if module_name do
            beam_pattern = "_build/**/#{module_name}.beam"
            Path.wildcard(beam_pattern) |> Enum.each(&File.rm/1)
          end

          test_result =
            Muex.TestRunner.Port.run_tests(test_files, original_file, timeout_ms: timeout_ms)

          File.write!(original_file, original_source)
          File.rm(backup_file)
          classify_test_result(test_result)

        {:error, reason} ->
          {:invalid, reason}
      end

    duration_ms = System.monotonic_time(:millisecond) - start_time

    {result_type, error} =
      case result do
        {:invalid, err} -> {:invalid, err}
        other -> {other, nil}
      end

    %{mutation: mutation, result: result_type, duration_ms: duration_ms, error: error}
  rescue
    e -> %{mutation: mutation, result: :timeout, duration_ms: 0, error: e}
  catch
    :exit, reason -> %{mutation: mutation, result: :timeout, duration_ms: 0, error: reason}
  end

  defp classify_test_result({:ok, %{failures: 0}}) do
    :survived
  end

  defp classify_test_result({:ok, %{failures: _}}) do
    :killed
  end

  defp classify_test_result({:error, :timeout}) do
    :timeout
  end

  defp classify_test_result({:error, _}) do
    :invalid
  end
end
