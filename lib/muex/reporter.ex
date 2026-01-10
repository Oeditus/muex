defmodule Muex.Reporter do
  @moduledoc """
  Reports mutation testing results to the terminal.

  Provides progress updates and final summaries of mutation testing runs.
  """

  @doc """
  Prints a summary of mutation testing results.

  ## Parameters

    - `results` - List of mutation results
  """
  @spec print_summary([map()]) :: :ok
  def print_summary(results) do
    total = length(results)
    killed = Enum.count(results, &(&1.result == :killed))
    survived = Enum.count(results, &(&1.result == :survived))
    invalid = Enum.count(results, &(&1.result == :invalid))
    timeout = Enum.count(results, &(&1.result == :timeout))

    mutation_score =
      if total > 0 do
        Float.round(killed / total * 100, 2)
      else
        0.0
      end

    IO.puts("\n")
    IO.puts("Mutation Testing Results")
    IO.puts(String.duplicate("=", 50))
    IO.puts("Total mutants: #{total}")
    IO.puts("Killed: #{killed} (caught by tests)")
    IO.puts("Survived: #{survived} (not caught by tests)")
    IO.puts("Invalid: #{invalid} (compilation errors)")
    IO.puts("Timeout: #{timeout}")
    IO.puts(String.duplicate("=", 50))
    IO.puts("Mutation Score: #{mutation_score}%")
    IO.puts("\n")

    if survived > 0 do
      print_survived_mutations(results)
    end

    :ok
  end

  @doc """
  Prints progress for a single mutation result.

  ## Parameters

    - `result` - A single mutation result
    - `index` - Current mutation index
    - `total` - Total number of mutations
  """
  @spec print_progress(map(), non_neg_integer(), non_neg_integer()) :: :ok
  def print_progress(result, index, total) do
    symbol =
      case result.result do
        :killed -> "✓"
        :survived -> "✗"
        :invalid -> "!"
        :timeout -> "⏱"
      end

    IO.write("\r[#{index}/#{total}] #{symbol}")
    :ok
  end

  defp print_survived_mutations(results) do
    survived = Enum.filter(results, &(&1.result == :survived))

    IO.puts("Survived Mutations:")
    IO.puts(String.duplicate("-", 50))

    Enum.each(survived, fn result ->
      mutation = result.mutation
      location = mutation.location

      IO.puts("#{location.file}:#{location.line}")
      IO.puts("  #{mutation.description}")
      IO.puts("")
    end)
  end
end
