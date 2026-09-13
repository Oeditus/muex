defmodule Muex.SinceTest do
  # Runs real mutants through `mix test` in a sandbox of a throwaway project,
  # and changes directory into it, so it cannot run alongside other tests.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Muex.Config

  @moduletag :tmp_dir
  @moduletag timeout: 180_000

  # The project sits in a subdirectory of its repository, as an umbrella inside a
  # monorepo does, and is loaded from relative paths, as `mix muex` run from the
  # project root loads it. Git names the changed file project/lib/tiny.ex; muex
  # names it lib/tiny.ex. Before --relative, nothing matched and the run
  # generated no mutations at all.
  test "--since finds the changed lines of a project in a subdirectory of its repository",
       %{tmp_dir: tmp_dir} do
    project = Path.join(tmp_dir, "project")
    write_tiny_project!(project)
    git!(["init", "-q"], tmp_dir)
    git!(["config", "user.email", "t@example.com"], tmp_dir)
    git!(["config", "user.name", "Test"], tmp_dir)
    git!(["add", "."], tmp_dir)
    git!(["commit", "-q", "-m", "init"], tmp_dir)

    File.write!(Path.join(project, "lib/tiny.ex"), """
    defmodule Tiny do
      def add(a, b), do: a + b
      def double(x), do: x * 3
    end
    """)

    git!(["commit", "-q", "-am", "change double/1"], tmp_dir)

    File.cd!(project, fn ->
      capture_io(fn ->
        assert {:ok, %{results: results}} = Muex.run(config!(project))
        assert [_ | _] = results
        assert Enum.all?(results, &(&1.mutation.location.line == 3))
      end)
    end)
  end

  defp config!(project) do
    {:ok, config} =
      Config.from_opts(
        files: "lib",
        test_paths: "test",
        project_root: project,
        mutators: "arithmetic",
        concurrency: 1,
        timeout: 60_000,
        no_filter: true,
        no_optimize: true,
        since: "HEAD~1"
      )

    config
  end

  defp git!(args, dir), do: {_, 0} = System.cmd("git", args, cd: dir, stderr_to_stdout: true)

  defp write_tiny_project!(root) do
    File.mkdir_p!(Path.join(root, "lib"))
    File.mkdir_p!(Path.join(root, "test"))

    File.write!(Path.join(root, "mix.exs"), """
    defmodule Tiny.MixProject do
      use Mix.Project

      def project, do: [app: :tiny, version: "0.1.0", elixir: "~> 1.15"]
    end
    """)

    File.write!(Path.join(root, "lib/tiny.ex"), """
    defmodule Tiny do
      def add(a, b), do: a + b
      def double(x), do: x * 2
    end
    """)

    File.write!(Path.join(root, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(Path.join(root, "test/tiny_test.exs"), """
    defmodule TinyTest do
      use ExUnit.Case

      test "add/2" do
        assert Tiny.add(2, 3) == 5
      end
    end
    """)
  end
end
