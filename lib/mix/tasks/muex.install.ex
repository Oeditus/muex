if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Muex.Install do
    @moduledoc """
    Installs muex into a project.

    Run with `mix igniter.install muex` (which adds the dependency first) or
    `mix muex.install` if muex is already a dependency.

    Adds muex's generated artifacts — the `cover/` coverage directory and the
    `muex-report.{json,html}` reports — to `.gitignore`.
    """
    @shortdoc "Installs muex (ignores its generated artifacts)."

    use Igniter.Mix.Task

    @marker "# muex (mutation testing) artifacts"
    @entries """
    #{@marker}
    /cover/
    /muex-report.json
    /muex-report.html
    """

    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{group: :muex}
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      Igniter.create_or_update_file(igniter, ".gitignore", @entries, &append_entries/1)
    end

    defp append_entries(source) do
      content = Rewrite.Source.get(source, :content)

      if String.contains?(content, @marker) do
        source
      else
        Rewrite.Source.update(
          source,
          :content,
          ensure_trailing_newline(content) <> "\n" <> @entries
        )
      end
    end

    defp ensure_trailing_newline(content) do
      if String.ends_with?(content, "\n"), do: content, else: content <> "\n"
    end
  end
else
  defmodule Mix.Tasks.Muex.Install do
    @moduledoc "Installs muex into a project. Requires igniter."
    @shortdoc "Installs muex (requires igniter)."

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'muex.install' requires igniter.

      Add {:igniter, "~> 0.8", only: [:dev, :test]} to your deps and run
      `mix deps.get`, or install muex with `mix igniter.install muex`.

      See https://hexdocs.pm/igniter for more information.
      """)

      exit({:shutdown, 1})
    end
  end
end
