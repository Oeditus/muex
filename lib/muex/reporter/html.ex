defmodule Muex.Reporter.Html do
  @moduledoc """
  HTML reporter for mutation testing results.

  Generates an interactive HTML report with color-coded results.
  """

  @doc """
  Generates HTML report from mutation results.

  ## Parameters

    - `results` - List of mutation results
    - `opts` - Options:
      - `:output_file` - Path to output file (default: "muex-report.html")

  ## Returns

    `:ok` after writing the HTML file
  """
  @spec generate([map()], keyword()) :: :ok | {:error, term()}
  def generate(results, opts \\ []) do
    output_file = Keyword.get(opts, :output_file, "muex-report.html")

    html = build_html(results)
    File.write(output_file, html)
  end

  defp build_html(results) do
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

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Muex Mutation Testing Report</title>
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; margin: 20px; background: #f5f5f5; }
            .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
            h1 { color: #333; margin-bottom: 30px; }
            .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 15px; margin-bottom: 30px; }
            .summary-card { padding: 20px; border-radius: 6px; text-align: center; }
            .summary-card.total { background: #e8f4f8; border-left: 4px solid #0084c7; }
            .summary-card.killed { background: #e8f8e8; border-left: 4px solid #28a745; }
            .summary-card.survived { background: #fff3cd; border-left: 4px solid #ffc107; }
            .summary-card.invalid { background: #f8d7da; border-left: 4px solid #dc3545; }
            .summary-card.timeout { background: #e8e8e8; border-left: 4px solid #6c757d; }
            .summary-card h3 { margin: 0 0 10px 0; font-size: 14px; color: #666; text-transform: uppercase; }
            .summary-card .value { font-size: 32px; font-weight: bold; color: #333; }
            .score { font-size: 48px; font-weight: bold; text-align: center; margin: 30px 0; color: #{score_color(mutation_score)}; }
            table { width: 100%; border-collapse: collapse; margin-top: 20px; }
            th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
            th { background: #f8f9fa; font-weight: 600; }
            .status { padding: 4px 12px; border-radius: 12px; font-size: 12px; font-weight: 600; }
            .status.killed { background: #d4edda; color: #155724; }
            .status.survived { background: #fff3cd; color: #856404; }
            .status.invalid { background: #f8d7da; color: #721c24; }
            .status.timeout { background: #e2e3e5; color: #383d41; }
            .location { font-family: monospace; font-size: 13px; color: #6c757d; }
            .description { font-size: 14px; }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>Mutation Testing Report</h1>
            
            <div class="summary">
                <div class="summary-card total">
                    <h3>Total</h3>
                    <div class="value">#{total}</div>
                </div>
                <div class="summary-card killed">
                    <h3>Killed</h3>
                    <div class="value">#{killed}</div>
                </div>
                <div class="summary-card survived">
                    <h3>Survived</h3>
                    <div class="value">#{survived}</div>
                </div>
                <div class="summary-card invalid">
                    <h3>Invalid</h3>
                    <div class="value">#{invalid}</div>
                </div>
                <div class="summary-card timeout">
                    <h3>Timeout</h3>
                    <div class="value">#{timeout}</div>
                </div>
            </div>

            <div class="score">
                Mutation Score: #{mutation_score}%
            </div>

            <h2>Mutations</h2>
            <table>
                <thead>
                    <tr>
                        <th>Status</th>
                        <th>Location</th>
                        <th>Description</th>
                        <th>Duration</th>
                    </tr>
                </thead>
                <tbody>
                    #{Enum.map_join(results, "\n", &format_mutation_row/1)}
                </tbody>
            </table>
        </div>
    </body>
    </html>
    """
  end

  defp format_mutation_row(result) do
    mutation = result.mutation
    status_class = Atom.to_string(result.result)
    duration = Map.get(result, :duration_ms, 0)

    """
        <tr>
            <td><span class="status #{status_class}">#{status_class}</span></td>
            <td class="location">#{escape_html(mutation.location.file)}:#{mutation.location.line}</td>
            <td class="description">#{escape_html(mutation.description)}</td>
            <td>#{duration}ms</td>
        </tr>
    """
  end

  defp score_color(score) when score >= 80, do: "#28a745"
  defp score_color(score) when score >= 60, do: "#ffc107"
  defp score_color(_score), do: "#dc3545"

  defp escape_html(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
