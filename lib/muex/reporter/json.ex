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

  ## Returns

    `:ok` after writing the JSON file
  """
  @spec generate([map()], keyword()) :: :ok | {:error, term()}
  def generate(results, opts \\ []) do
    output_file = Keyword.get(opts, :output_file, "muex-report.json")

    report = build_report(results)
    json = Jason.encode!(report, pretty: true)

    File.write(output_file, json)
  end

  @doc """
  Returns JSON string from mutation results without writing to file.

  ## Parameters

    - `results` - List of mutation results

  ## Returns

    JSON string
  """
  @spec to_json([map()]) :: String.t()
  def to_json(results) do
    report = build_report(results)
    Jason.encode!(report, pretty: true)
  end

  defp build_report(results) do
    total = length(results)
    killed = Enum.count(results, &(&1.result == :killed))
    survived = Enum.count(results, &(&1.result == :survived))
    invalid = Enum.count(results, &(&1.result == :invalid))
    timeout = Enum.count(results, &(&1.result == :timeout))

    denom = killed + survived + timeout

    {score_low, score_high} =
      if denom > 0 do
        {Float.round(killed / denom * 100, 2), Float.round((killed + timeout) / denom * 100, 2)}
      else
        {0.0, 0.0}
      end

    %{
      summary: %{
        total: total,
        killed: killed,
        survived: survived,
        invalid: invalid,
        timeout: timeout,
        mutation_score_low: score_low,
        mutation_score_high: score_high
      },
      mutations: Enum.map(results, &format_mutation/1)
    }
  end

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
      error: format_error(Map.get(result, :error))
    }
  end

  defp format_error(nil), do: nil
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)
end
