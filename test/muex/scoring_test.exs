defmodule Muex.ScoringTest do
  # Runs real mutants through `mix test` in sandboxes of throwaway projects, so
  # it is slower than the unit tests around it and cannot run alongside them.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Muex.Config

  @moduletag :tmp_dir
  @moduletag timeout: 180_000

  # A test the environment leaves off (an :integration tag, a @tag :skip) still
  # lets `mix test` exit 0, with "0 tests" in the summary. Nothing ran against
  # the mutant, so it did not survive anything; it used to be scored survived.
  test "a mutant whose only test is skipped is scored no_coverage and not survived", %{
    tmp_dir: tmp_dir
  } do
    project = write_tiny_project!(tmp_dir, "@tag :skip")

    output =
      capture_io(fn ->
        assert {:ok, %{results: results}} = Muex.run(config!(project, "terminal"))
        tested = Enum.reject(results, &(&1.result == :equivalent))
        assert [_ | _] = tested

        for result <- tested do
          assert result.result == :no_coverage
          assert result.error =~ "0 tests ran: "
          assert result.error =~ "skipped"
          assert result.test_files == ["test/tiny_test.exs"]
        end
      end)

    assert output =~ "had tests chosen, but 0 tests ran"
    refute output =~ "Survived Mutations"
  end

  # Muex.Equivalence drops `x + 0` to `x - 0` before the run. It is still a
  # result, so the report shows what was judged equivalent.
  test "equivalent mutants are reported and not dropped", %{tmp_dir: tmp_dir} do
    project = write_tiny_project!(tmp_dir, "")
    report_path = Path.join(tmp_dir, "muex.json")

    capture_io(fn ->
      assert {:ok, %{results: results}} = Muex.run(config!(project, "json", output: report_path))
      assert Enum.any?(results, &(&1.result == :equivalent))
    end)

    report = report_path |> File.read!() |> Jason.decode!()
    [equivalent] = Enum.filter(report["mutations"], &(&1["status"] == "equivalent"))

    assert equivalent["location"]["line"] == 3
    assert equivalent["description"] =~ "+ to -"
    assert equivalent["error"] =~ "cannot change behaviour"
    assert report["summary"]["equivalent"] == 1
    assert report["summary"]["no_coverage"] == 0

    # Left out of the score: add/2's two mutants are killed, same/1's other
    # mutant (x + 0 to 0) survives because the test never checks same/1.
    assert report["summary"]["mutation_score_low"] == 66.67
  end

  # The umbrella baseline runs the chosen tests once with no mutation. When all
  # of them are skipped it used to report green and go on to score every mutant.
  test "an umbrella whose chosen tests all skip is refused at the baseline",
       %{tmp_dir: tmp_dir} do
    umbrella = write_umbrella!(tmp_dir)

    {result, _stderr} =
      with_io(:stderr, fn ->
        {result, _stdout} = with_io(fn -> Muex.run(umbrella_config!(umbrella)) end)
        result
      end)

    assert {:error, message} = result
    assert message =~ "ran 0 tests with NO mutation"
    assert message =~ "apps/a/test/a_test.exs"
  end

  defp config!(project, format, extra \\ []) do
    opts =
      [
        files: Path.join(project, "lib"),
        test_paths: Path.join(project, "test"),
        project_root: project,
        mutators: "arithmetic",
        concurrency: 1,
        timeout: 60_000,
        no_filter: true,
        no_optimize: true,
        format: format
      ] ++ extra

    {:ok, config} = Config.from_opts(opts)
    config
  end

  defp umbrella_config!(umbrella) do
    {:ok, config} =
      Config.from_opts(
        files: Path.join(umbrella, "apps/a/lib"),
        test_paths: Path.join(umbrella, "apps/a/test"),
        project_root: umbrella,
        mutators: "arithmetic",
        concurrency: 1,
        timeout: 60_000,
        no_filter: true,
        no_optimize: true
      )

    config
  end

  defp write_tiny_project!(tmp_dir, tag) do
    root = Path.join(tmp_dir, "tiny")

    write_files!(root, %{
      "mix.exs" => """
      defmodule Tiny.MixProject do
        use Mix.Project
        def project, do: [app: :tiny, version: "0.1.0", elixir: "~> 1.15"]
      end
      """,
      "lib/tiny.ex" => """
      defmodule Tiny do
        def add(a, b), do: a + b
        def same(x), do: x + 0
      end
      """,
      "test/test_helper.exs" => "ExUnit.start()\n",
      "test/tiny_test.exs" => """
      defmodule TinyTest do
        use ExUnit.Case
        #{tag}
        test "add/2" do
          assert Tiny.add(2, 3) == 5
        end
      end
      """
    })

    root
  end

  defp write_umbrella!(tmp_dir) do
    root = Path.join(tmp_dir, "umbrella")

    write_files!(root, %{
      "mix.exs" => """
      defmodule Umbrella.MixProject do
        use Mix.Project
        def project, do: [apps_path: "apps", version: "0.1.0", deps: []]
      end
      """,
      "config/config.exs" => "import Config\n",
      "apps/a/mix.exs" => """
      defmodule A.MixProject do
        use Mix.Project

        def project do
          [
            app: :a,
            version: "0.1.0",
            build_path: "../../_build",
            config_path: "../../config/config.exs",
            deps_path: "../../deps",
            lockfile: "../../mix.lock"
          ]
        end
      end
      """,
      "apps/a/lib/a.ex" => "defmodule A do\n  def two, do: 1 + 1\nend\n",
      "apps/a/test/test_helper.exs" => "ExUnit.start()\n",
      "apps/a/test/a_test.exs" => """
      defmodule ATest do
        use ExUnit.Case
        @tag :skip
        test "two/0" do
          assert A.two() == 2
        end
      end
      """
    })

    root
  end

  defp write_files!(root, files) do
    for {path, content} <- files do
      full = Path.join(root, path)
      File.mkdir_p!(Path.dirname(full))
      File.write!(full, content)
    end
  end
end
