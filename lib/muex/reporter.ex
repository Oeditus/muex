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

    # Invalids are excluded: they say nothing about test quality.
    # Timeouts are ambiguous -- could be killed or survived.
    denom = killed + survived + timeout

    {score_low, score_high} =
      if denom > 0 do
        low = Float.round(killed / denom * 100, 2)
        high = Float.round((killed + timeout) / denom * 100, 2)
        {low, high}
      else
        {0.0, 0.0}
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
        score_low >= 80 -> @green
        score_low >= 60 -> @yellow
        true -> @red
      end

    score_str =
      if score_low == score_high do
        "#{score_low}%"
      else
        "#{score_low}%..#{score_high}%"
      end

    IO.puts("#{@bold}Mutation Score: #{score_color}#{score_str}#{@reset}")
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
        :killed -> {"·", @green}
        :survived -> {"×", @red}
        :invalid -> {"-", @yellow}
        :timeout -> {"?", @magenta}
      end

    IO.write("#{color}#{symbol}#{@reset}")

    # Add newline every 80 dots or at the end
    if rem(index, 80) == 0 or index == total do
      IO.write("\n")
    end

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
      print_patch(Muex.Reporter.Patch.of(mutation))
      IO.puts("")
    end)
  end

  defp print_patch(%{before: before_snippet, after: after_snippet}) do
    IO.puts("    #{@red}- #{before_snippet}#{@reset}")
    IO.puts("    #{@green}+ #{after_snippet}#{@reset}")
  end

  defp print_patch(_patch), do: :ok
end
