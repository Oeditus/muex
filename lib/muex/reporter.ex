defmodule Muex.Reporter do
  @moduledoc """
  Reports mutation testing results to the terminal.

  Provides progress updates and final summaries of mutation testing runs.
  """

  alias Muex.Reporter.Patch

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

    %{
      killed: killed,
      survived: survived,
      invalid: invalid,
      timeout: timeout,
      equivalent: equivalent,
      no_coverage: no_coverage
    } = count_by_status(results)

    score = score_range(killed, survived, timeout)
    {score_low, _score_high} = score

    IO.puts("\n")
    IO.puts("#{@bold}#{@cyan}Mutation Testing Results#{@reset}")
    IO.puts("#{@gray}#{String.duplicate("=", 50)}#{@reset}")
    IO.puts("#{@bold}Total mutants:#{@reset} #{total}")
    IO.puts("#{@green}Killed:#{@reset} #{killed} #{@gray}(caught by tests)#{@reset}")
    IO.puts("#{@red}Survived:#{@reset} #{survived} #{@gray}(not caught by tests)#{@reset}")
    IO.puts("#{@yellow}Invalid:#{@reset} #{invalid} #{@gray}(compilation errors)#{@reset}")
    IO.puts("#{@magenta}Timeout:#{@reset} #{timeout}")

    if equivalent > 0 do
      IO.puts(
        "#{@gray}Equivalent:#{@reset} #{equivalent} #{@gray}(provably unkillable, skipped)#{@reset}"
      )
    end

    if no_coverage > 0 do
      IO.puts(
        "#{@gray}No coverage:#{@reset} #{no_coverage} #{@gray}(no test exercises the line, skipped)#{@reset}"
      )
    end

    IO.puts("#{@gray}#{String.duplicate("=", 50)}#{@reset}")

    score_color =
      cond do
        score_low >= 80 -> @green
        score_low >= 60 -> @yellow
        true -> @red
      end

    IO.puts("#{@bold}Mutation Score: #{score_color}#{format_score(score)}#{@reset}")
    IO.puts("\n")

    if survived > 0 do
      print_survived_mutations(results)
    end

    :ok
  end

  @doc """
  Returns a one-line, uncolored summary of the results, such as
  `"Mutation Score: 75.0% (4 mutants: 3 killed, 1 survived, 0 invalid, 0 timed out)"`.

  Equivalent and no-coverage mutants are counted only when there are any, as in
  `print_summary/1`. Printed in place of the full summary when the report is
  written to a file.
  """
  @spec summary_line([map()]) :: String.t()
  def summary_line(results) do
    counts = count_by_status(results)
    score = format_score(score_range(counts.killed, counts.survived, counts.timeout))

    parts =
      [
        "#{counts.killed} killed",
        "#{counts.survived} survived",
        "#{counts.invalid} invalid",
        "#{counts.timeout} timed out"
      ] ++
        for {status, label} <- [equivalent: "equivalent", no_coverage: "no coverage"],
            counts[status] > 0,
            do: "#{counts[status]} #{label}"

    "Mutation Score: #{score} (#{length(results)} mutants: #{Enum.join(parts, ", ")})"
  end

  @statuses [:killed, :survived, :invalid, :timeout, :equivalent, :no_coverage]

  defp count_by_status(results) do
    frequencies = Enum.frequencies_by(results, & &1.result)
    Map.new(@statuses, &{&1, Map.get(frequencies, &1, 0)})
  end

  # Invalids, equivalents, and no-coverage mutants are excluded: none of them
  # says anything about test quality (an equivalent mutant can never be
  # killed, and a no-coverage line has no test that could kill it).
  # Timeouts are ambiguous -- could be killed or survived -- so the score is a
  # range: the low bound counts them as survived, the high bound as killed.
  defp score_range(killed, survived, timeout) do
    denom = killed + survived + timeout

    if denom > 0 do
      low = Float.round(killed / denom * 100, 2)
      high = Float.round((killed + timeout) / denom * 100, 2)
      {low, high}
    else
      {0.0, 0.0}
    end
  end

  defp format_score({score, score}), do: "#{score}%"
  defp format_score({low, high}), do: "#{low}%..#{high}%"

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
        :equivalent -> {"≡", @gray}
        :no_coverage -> {"∅", @gray}
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
      print_patch(Patch.of(mutation))
      print_test_files(Map.get(result, :test_files, []))
      IO.puts("")
    end)
  end

  # A survivor's test files all ran and passed anyway; naming them points at the
  # assertion that is missing or too weak.
  defp print_test_files([]), do: :ok

  defp print_test_files(test_files),
    do: IO.puts("    #{@gray}Test files: #{Enum.join(test_files, ", ")}#{@reset}")

  defp print_patch(%{before: before_snippet, after: after_snippet}) do
    IO.puts("    #{@red}- #{before_snippet}#{@reset}")
    IO.puts("    #{@green}+ #{after_snippet}#{@reset}")
  end

  defp print_patch(_patch), do: :ok
end
