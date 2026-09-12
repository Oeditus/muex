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
    equivalent = Enum.count(results, &(&1.result == :equivalent))
    no_coverage = Enum.count(results, &(&1.result == :no_coverage))

    denom = killed + survived + timeout

    score_str =
      if denom > 0 do
        low = Float.round(killed / denom * 100, 2)
        high = Float.round((killed + timeout) / denom * 100, 2)
        if low == high, do: "#{low}%", else: "#{low}%..#{high}%"
      else
        "0.0%"
      end

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Muex Mutation Testing Report</title>
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
          line-height: 1.6;
          color: #333;
          background: #f5f5f5;
          padding: 20px;
        }
        .container {
          max-width: 1200px;
          margin: 0 auto;
          background: white;
          padding: 30px;
          border-radius: 8px;
          box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 {
          color: #2c3e50;
          margin-bottom: 30px;
          padding-bottom: 15px;
          border-bottom: 3px solid #3498db;
        }
        .summary {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
          gap: 20px;
          margin-bottom: 30px;
        }
        .summary-card {
          padding: 20px;
          border-radius: 6px;
          text-align: center;
        }
        .summary-card.total { background: #ecf0f1; border-left: 4px solid #95a5a6; }
        .summary-card.killed { background: #d5f4e6; border-left: 4px solid #27ae60; }
        .summary-card.survived { background: #fadbd8; border-left: 4px solid #e74c3c; }
        .summary-card.invalid { background: #fff4e6; border-left: 4px solid #f39c12; }
        .summary-card.timeout { background: #e8daef; border-left: 4px solid #8e44ad; }
        .summary-card.equivalent { background: #eef2f3; border-left: 4px solid #7f8c8d; }
        .summary-card.no_coverage { background: #eef2f3; border-left: 4px solid #34495e; }
        .summary-card.score {
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
          color: white;
          border: none;
          font-size: 1.2em;
        }
        .summary-number {
          font-size: 2.5em;
          font-weight: bold;
          margin: 10px 0;
        }
        .summary-label {
          font-size: 0.9em;
          text-transform: uppercase;
          letter-spacing: 1px;
          opacity: 0.8;
        }
        .filters {
          margin-bottom: 20px;
          display: flex;
          gap: 10px;
          flex-wrap: wrap;
        }
        .filter-btn {
          padding: 8px 16px;
          border: 2px solid #ddd;
          background: white;
          border-radius: 4px;
          cursor: pointer;
          transition: all 0.2s;
        }
        .filter-btn:hover { background: #f8f9fa; }
        .filter-btn.active {
          background: #3498db;
          color: white;
          border-color: #3498db;
        }
        .mutations {
          display: flex;
          flex-direction: column;
          gap: 15px;
        }
        .mutation {
          padding: 15px;
          border-radius: 6px;
          border-left: 4px solid;
          background: #fafafa;
        }
        .mutation.killed { border-left-color: #27ae60; }
        .mutation.survived { border-left-color: #e74c3c; }
        .mutation.invalid { border-left-color: #f39c12; }
        .mutation.timeout { border-left-color: #8e44ad; }
        .mutation.equivalent { border-left-color: #7f8c8d; }
        .mutation.no_coverage { border-left-color: #34495e; }
        .mutation-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 10px;
        }
        .mutation-status {
          padding: 4px 12px;
          border-radius: 4px;
          font-size: 0.85em;
          font-weight: 600;
          text-transform: uppercase;
        }
        .status-killed { background: #27ae60; color: white; }
        .status-survived { background: #e74c3c; color: white; }
        .status-invalid { background: #f39c12; color: white; }
        .status-timeout { background: #8e44ad; color: white; }
        .status-equivalent { background: #7f8c8d; color: white; }
        .status-no_coverage { background: #34495e; color: white; }
        .mutation-location {
          font-family: 'Monaco', 'Courier New', monospace;
          font-size: 0.9em;
          color: #555;
        }
        .mutation-body {
          display: flex;
          flex-direction: column;
          gap: 8px;
        }
        .mutation-mutator {
          color: #8e44ad;
          font-weight: 600;
          font-size: 0.9em;
        }
        .mutation-description {
          color: #555;
        }
        .mutation-tests {
          color: #555;
          font-family: 'Monaco', 'Courier New', monospace;
          font-size: 0.85em;
          margin-top: 5px;
        }
        .mutation-error {
          background: #fff5f5;
          border: 1px solid #feb2b2;
          border-radius: 4px;
          padding: 10px;
          font-family: 'Monaco', 'Courier New', monospace;
          font-size: 0.85em;
          color: #c53030;
          margin-top: 5px;
        }
        .hidden { display: none; }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>Muex Mutation Testing Report</h1>
        
        <div class="summary">
          <div class="summary-card total">
            <div class="summary-label">Total Mutants</div>
            <div class="summary-number">#{total}</div>
          </div>
          <div class="summary-card killed">
            <div class="summary-label">Killed</div>
            <div class="summary-number">#{killed}</div>
          </div>
          <div class="summary-card survived">
            <div class="summary-label">Survived</div>
            <div class="summary-number">#{survived}</div>
          </div>
          <div class="summary-card invalid">
            <div class="summary-label">Invalid</div>
            <div class="summary-number">#{invalid}</div>
          </div>
          <div class="summary-card timeout">
            <div class="summary-label">Timeout</div>
            <div class="summary-number">#{timeout}</div>
          </div>
          <div class="summary-card equivalent">
            <div class="summary-label">Equivalent</div>
            <div class="summary-number">#{equivalent}</div>
          </div>
          <div class="summary-card no_coverage">
            <div class="summary-label">No Coverage</div>
            <div class="summary-number">#{no_coverage}</div>
          </div>
          <div class="summary-card score">
            <div class="summary-label">Mutation Score</div>
            <div class="summary-number">#{score_str}</div>
          </div>
        </div>

        <div class="filters">
          <button class="filter-btn active" data-filter="all">All</button>
          <button class="filter-btn" data-filter="killed">Killed</button>
          <button class="filter-btn" data-filter="survived">Survived</button>
          <button class="filter-btn" data-filter="invalid">Invalid</button>
          <button class="filter-btn" data-filter="timeout">Timeout</button>
          <button class="filter-btn" data-filter="equivalent">Equivalent</button>
          <button class="filter-btn" data-filter="no_coverage">No Coverage</button>
        </div>

        <div class="mutations">
          #{Enum.map_join(results, "\n", &format_mutation_html/1)}
        </div>
      </div>

      <script>
        document.addEventListener('DOMContentLoaded', function() {
          const filterBtns = document.querySelectorAll('.filter-btn');
          const mutations = document.querySelectorAll('.mutation');

          filterBtns.forEach(btn => {
            btn.addEventListener('click', function() {
              const filter = this.dataset.filter;
              
              filterBtns.forEach(b => b.classList.remove('active'));
              this.classList.add('active');

              mutations.forEach(mutation => {
                if (filter === 'all' || mutation.classList.contains(filter)) {
                  mutation.classList.remove('hidden');
                } else {
                  mutation.classList.add('hidden');
                }
              });
            });
          });
        });
      </script>
    </body>
    </html>
    """
  end

  defp format_mutation_html(result) do
    mutation = result.mutation
    status = Atom.to_string(result.result)
    error = format_error_html(Map.get(result, :error))
    test_files = format_test_files_html(Map.get(result, :test_files, []))

    """
          <div class="mutation #{status}">
            <div class="mutation-header">
              <div class="mutation-location">#{mutation.location.file}:#{mutation.location.line}</div>
              <div class="mutation-status status-#{status}">#{status}</div>
            </div>
            <div class="mutation-body">
              <div class="mutation-mutator">#{format_mutator(mutation.mutator)}</div>
              <div class="mutation-description">#{escape_html(mutation.description)}</div>
              #{test_files}
              #{error}
            </div>
          </div>
    """
  end

  defp format_test_files_html([]), do: ""

  defp format_test_files_html(test_files) do
    """
              <div class="mutation-tests">Test files: #{escape_html(Enum.join(test_files, ", "))}</div>
    """
  end

  defp format_mutator(mutator) do
    mutator
    |> Module.split()
    |> List.last()
  end

  defp format_error_html(nil), do: ""

  defp format_error_html(error) do
    """
              <div class="mutation-error">#{escape_html(format_error(error))}</div>
    """
  end

  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)

  defp escape_html(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  defp escape_html(text), do: text
end
