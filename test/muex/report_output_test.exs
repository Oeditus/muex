defmodule Muex.ReportOutputTest do
  # Runs real mutants through `mix test` in a sandbox of a throwaway project,
  # so it is slower than the unit tests around it.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Muex.Config

  @moduletag :tmp_dir
  @moduletag timeout: 180_000

  test "--output writes the report to the file and records each mutant's test files",
       %{tmp_dir: tmp_dir} do
    project = write_tiny_project!(tmp_dir)
    report_path = Path.join([tmp_dir, "reports", "muex.json"])

    output =
      capture_io(fn -> assert {:ok, _} = Muex.run(config!(project, "json", report_path)) end)

    assert output =~ "Mutation Score: 50.0% (4 mutants: 2 killed, 2 survived"
    assert output =~ "Report: #{report_path}"
    refute output =~ "\"mutations\""

    report = report_path |> File.read!() |> Jason.decode!()
    by_line = Enum.group_by(report["mutations"], & &1["location"]["line"])

    # add/2 is tested: its mutants are killed by the test that calls it.
    killed = %{"status" => "killed", "test_files" => ["test/tiny_test.exs"]}
    assert [^killed, ^killed] = Enum.map(by_line[2], &Map.take(&1, ["status", "test_files"]))

    # double/1 is not: its mutants survive, and the report names the test file
    # that ran and passed anyway.
    survived = %{"status" => "survived", "test_files" => ["test/tiny_test.exs"]}
    assert [^survived, ^survived] = Enum.map(by_line[3], &Map.take(&1, ["status", "test_files"]))
  end

  test "--output writes the HTML report to the file", %{tmp_dir: tmp_dir} do
    project = write_tiny_project!(tmp_dir)
    report_path = Path.join(tmp_dir, "muex.html")

    output =
      capture_io(fn -> assert {:ok, _} = Muex.run(config!(project, "html", report_path)) end)

    assert output =~ "Report: #{report_path}"
    assert File.read!(report_path) =~ "Test files: test/tiny_test.exs"
  end

  test "json without --output prints the report to stdout", %{tmp_dir: tmp_dir} do
    project = write_tiny_project!(tmp_dir)

    output = capture_io(fn -> assert {:ok, _} = Muex.run(config!(project, "json", nil)) end)

    assert output =~ "\"mutations\""
    assert output =~ "\"test_files\""
    refute output =~ "Report:"
  end

  test "html without --output writes muex-report.html in the working directory",
       %{tmp_dir: tmp_dir} do
    project = write_tiny_project!(tmp_dir)

    File.cd!(tmp_dir, fn ->
      capture_io(fn -> assert {:ok, _} = Muex.run(config!(project, "html", nil)) end)
      assert File.read!("muex-report.html") =~ "Test files: test/tiny_test.exs"
    end)
  end

  test "a failed write of the default HTML report is an error", %{tmp_dir: tmp_dir} do
    project = write_tiny_project!(tmp_dir)

    File.cd!(tmp_dir, fn ->
      File.mkdir_p!("muex-report.html")

      capture_io(fn ->
        assert {:error, message} = Muex.run(config!(project, "html", nil))
        assert message =~ "Could not write the report to muex-report.html"
      end)
    end)
  end

  test "the terminal format prints the full summary", %{tmp_dir: tmp_dir} do
    project = write_tiny_project!(tmp_dir)

    output =
      capture_io(fn ->
        assert {:ok, _} = Muex.run(config!(project, "terminal", nil, verbose: true))
      end)

    assert output =~ "Loading files from"
    assert output =~ "Mutation Testing Results"
    assert output =~ "Test files: test/tiny_test.exs"
  end

  # A project with nothing to mutate would otherwise answer {:ok, _}, so an error
  # here shows the path is checked before files are even loaded.
  test "an unwritable --output path is refused before the run", %{tmp_dir: tmp_dir} do
    project = Path.join(tmp_dir, "empty")
    File.mkdir_p!(Path.join(project, "lib"))
    not_a_dir = Path.join(tmp_dir, "file")
    File.write!(not_a_dir, "")

    assert {:error, message} =
             Muex.run(config!(project, "json", Path.join(not_a_dir, "muex.json")))

    assert message =~ "Could not write the report to #{not_a_dir}/muex.json"
  end

  test "checking the --output path leaves no file behind", %{tmp_dir: tmp_dir} do
    project = Path.join(tmp_dir, "empty")
    File.mkdir_p!(Path.join(project, "lib"))
    report_path = Path.join(tmp_dir, "muex.json")

    assert {:ok, %{results: []}} = Muex.run(config!(project, "json", report_path))
    refute File.exists?(report_path)
  end

  defp config!(project, format, output, extra \\ []) do
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
        format: format,
        output: output
      ] ++ extra

    {:ok, config} = Config.from_opts(opts)
    config
  end

  defp write_tiny_project!(tmp_dir) do
    root = Path.join(tmp_dir, "tiny")
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

    root
  end
end
