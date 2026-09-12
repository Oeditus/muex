defmodule Muex.Runner do
  @moduledoc """
  Runs tests against mutated code.

  Executes the test suite for each mutation and classifies the results.
  """

  @type result :: :killed | :survived | :invalid | :timeout
  @type mutation_result :: %{
          mutation: map(),
          result: result(),
          duration_ms: non_neg_integer(),
          error: term() | nil
        }
  @doc """
  Runs all mutations in parallel using a global worker pool with sandbox isolation.

  Mutations targeting different files run concurrently. Mutations targeting the
  same file are serialized via per-file locking.

  ## Parameters

    - `mutations` - List of all mutations to test (across all files)
    - `file_entries` - Map of file paths to file entry maps
    - `language_adapter` - The language adapter module
    - `dependency_map` - Map of modules to test files
    - `file_to_module` - Map of file paths to module names
    - `opts` - Options:
      - `:max_workers` - Maximum concurrent workers (default: 4)
      - `:timeout_ms` - Test timeout in milliseconds (default: 5000)
      - `:test_paths` - List of test path patterns (default: ["test"])
      - `:verbose` - Show progress (default: false)

  ## Returns

    List of `mutation_result` maps, or `{:error, reason}` when the run was
    refused before any mutant ran (see `Muex.Sandbox.Error`).
  """
  @spec run_all([map()], %{Path.t() => map()}, module(), map(), map(), keyword()) ::
          [mutation_result()] | {:error, String.t()}
  def run_all(
        mutations,
        file_entries,
        language_adapter,
        dependency_map,
        file_to_module,
        opts \\ []
      ) do
    max_workers = Keyword.get(opts, :max_workers, 4)
    {:ok, pool} = Muex.WorkerPool.start_link(max_workers: max_workers)

    try do
      Muex.WorkerPool.run_mutations(
        pool,
        mutations,
        file_entries,
        language_adapter,
        dependency_map,
        file_to_module,
        opts
      )
    after
      GenServer.stop(pool, :normal, :infinity)
    end
  end
end
