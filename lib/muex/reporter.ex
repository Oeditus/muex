defmodule Muex.Reporter do
  @moduledoc """
  Reports mutation testing results to the terminal.

  Provides progress updates and final summaries of mutation testing runs.
  """

  # ANSI color codes
  @reset "\e[0m"
  @bold "\e[1m"
  @green "\e[32m"
  @red "\e[31m"
  @yellow "\e[33m"
  @magenta "\e[35m"
  @cyan "\e[36m"
  @gray "\e[90m"

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
    IO.puts("#{@bold}#{@cyan}Mutation Testing Results#{@reset}")
    IO.puts("#{@gray}#{String.duplicate("=", 50)}#{@reset}")
    IO.puts("#{@bold}Total mutants:#{@reset} #{total}")
    IO.puts("#{@green}Killed:#{@reset} #{killed} #{@gray}(caught by tests)#{@reset}")
    IO.puts("#{@red}Survived:#{@reset} #{survived} #{@gray}(not caught by tests)#{@reset}")
    IO.puts("#{@yellow}Invalid:#{@reset} #{invalid} #{@gray}(compilation errors)#{@reset}")
    IO.puts("#{@magenta}Timeout:#{@reset} #{timeout}")
    IO.puts("#{@gray}#{String.duplicate("=", 50)}#{@reset}")

    score_color =
      cond do
        mutation_score >= 80 -> @green
        mutation_score >= 60 -> @yellow
        true -> @red
      end

    IO.puts("#{@bold}Mutation Score: #{score_color}#{mutation_score}%#{@reset}")
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
    {symbol, color} =
      case result.result do
        :killed -> {"✓", @green}
        :survived -> {"✗", @red}
        :invalid -> {"!", @yellow}
        :timeout -> {"⏱", @magenta}
      end

    IO.write("\r#{@gray}[#{index}/#{total}]#{@reset} #{color}#{symbol}#{@reset}")
    :ok
  end

  defp print_survived_mutations(results) do
    survived = Enum.filter(results, &(&1.result == :survived))

    IO.puts("#{@bold}#{@red}Survived Mutations:#{@reset}")
    IO.puts("#{@gray}#{String.duplicate("-", 50)}#{@reset}")

    Enum.each(survived, fn result ->
      mutation = result.mutation
      location = mutation.location

      IO.puts("#{@cyan}#{location.file}:#{location.line}#{@reset}")
      IO.puts("  #{@yellow}#{mutation.description}#{@reset}")
      IO.puts("")
    end)
  end
end
