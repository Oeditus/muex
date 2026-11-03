defmodule Muex.Reporter.Json do
  @moduledoc """
  JSON reporter for mutation testing results.

  Exports results in structured JSON format for CI/CD integration.

  Each mutation entry includes a `patch` object with `before` and `after`
  code snippets (or `null` when the mutation does not carry the original and
  mutated AST), so survived mutants can be reproduced from the report alone.
  """

  alias Muex.Reporter.Patch

  @doc """
  Generates JSON report from mutation results.

  ## Parameters

    - `results` - List of mutation results
    - `opts` - Options:
      - `:output_file` - Path to output file (default: "muex-report.json")
      - `:partial` - `%{mutations_run: n, mutations_total: m}` when the run hit
        its deadline; adds `partial: true`, `mutations_run` and `mutations_total`
        to the summary. Absent otherwise, so a complete report is unchanged.

  ## Returns

    `:ok` after writing the JSON file
  """
  @spec generate([map()], keyword()) :: :ok | {:error, term()}
  def generate(results, opts \\ []) do
    output_file = Keyword.get(opts, :output_file, "muex-report.json")

    report = build_report(results, opts)
    json = Jason.encode!(report, pretty: true)

    File.write(output_file, json)
  end

  @doc """
  Returns JSON string from mutation results without writing to file.

  ## Parameters

    - `results` - List of mutation results
    - `opts` - As for `generate/2` (`:partial`)

  ## Returns

    JSON string
  """
  @spec to_json([map()], keyword()) :: String.t()
  def to_json(results, opts \\ []) do
    report = build_report(results, opts)
    Jason.encode!(report, pretty: true)
  end

  defp build_report(results, opts) do
    total = length(results)
    killed = Enum.count(results, &(&1.result == :killed))
    survived = Enum.count(results, &(&1.result == :survived))
    invalid = Enum.count(results, &(&1.result == :invalid))
    timeout = Enum.count(results, &(&1.result == :timeout))
    equivalent = Enum.count(results, &(&1.result == :equivalent))
    no_coverage = Enum.count(results, &(&1.result == :no_coverage))

    denom = killed + survived + timeout

    {score_low, score_high} =
      if denom > 0 do
        {Float.round(killed / denom * 100, 2), Float.round((killed + timeout) / denom * 100, 2)}
      else
        {0.0, 0.0}
      end

    summary = %{
      total: total,
      killed: killed,
      survived: survived,
      invalid: invalid,
      timeout: timeout,
      equivalent: equivalent,
      no_coverage: no_coverage,
      mutation_score_low: score_low,
      mutation_score_high: score_high
    }

    %{
      summary: Map.merge(summary, partial_summary(Keyword.get(opts, :partial))),
      mutations: Enum.map(results, &format_mutation/1)
    }
  end

  defp partial_summary(nil), do: %{}

  defp partial_summary(%{mutations_run: run, mutations_total: total}),
    do: %{partial: true, mutations_run: run, mutations_total: total}

  defp format_mutation(result) do
    mutation = result.mutation

    %{
      status: result.result,
      mutator: inspect(mutation.mutator),
      description: mutation.description,
      location: %{
        file: mutation.location.file,
        line: mutation.location.line
      },
      patch: Patch.of(mutation),
      duration_ms: Map.get(result, :duration_ms, 0),
      error: format_error(Map.get(result, :error)),
      test_files: Map.get(result, :test_files, [])
    }
  end

  defp format_error(nil), do: nil
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)
end
