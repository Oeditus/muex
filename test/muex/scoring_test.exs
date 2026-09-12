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
    assert equivalent["error"] =~ "judged equivalent by Muex.Equivalence"
    assert report["summary"]["equivalent"] == 1
    assert report["summary"]["no_coverage"] == 0

    # Left out of the score: add/2's two mutants are killed, same/1's other
    # mutant (x + 0 to 0) survives because the test never checks same/1.
    assert report["summary"]["mutation_score_low"] == 66.67
  end

  # With only equivalent mutants left there is nothing to score. They are still
  # reported, but the result is the same as a run with no mutants, so the CLI
  # and the Mix task exit as they did before equivalents were reported.
  test "a run with only equivalent mutants left reports them and scores nothing",
       %{tmp_dir: tmp_dir} do
    project = write_tiny_project!(tmp_dir, "")

    {:ok, config} =
      Config.from_opts(
        files: Path.join(project, "lib"),
        test_paths: Path.join(project, "test"),
        project_root: project,
        mutators: "arithmetic",
        concurrency: 1,
        timeout: 60_000,
        no_filter: true,
        # The optimizer drops every mutant that is not equivalent.
        min_complexity: 99
      )

    output =
      capture_io(fn ->
        assert {:ok, %{results: [], score_low: +0.0, score_high: +0.0}} = Muex.run(config)
      end)

    assert output =~ "Equivalent:"
    assert output =~ "Total mutants:"
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

  # A file the mutant does not touch fails to compile (here from the start; in
  # the run that found this, a dependency edited mid-run). Every mutant would
  # come back invalid, blamed for an error in another file, and the score would
  # read as if the run were healthy. It stops instead and names the file.
  #
  # The mutated file also prints a warning of its own, which the compiler shows
  # beside the error: it is not the error's cause and must not be read as one.
  test "a compile error in a file the mutant did not touch stops the run and names the file",
       %{tmp_dir: tmp_dir} do
    project = write_tiny_project!(tmp_dir, "")

    File.write!(lib_file(project), """
    defmodule Tiny do
      def add(a, b), do: a + b
      def noisy(unused), do: 1
    end
    """)

    File.write!(
      Path.join(project, "lib/broken.ex"),
      "defmodule Broken do\n  def f, do: nope()\nend\n"
    )

    assert {:error, message} = run_quietly(config!(project, "terminal", files: lib_file(project)))
    assert message =~ "Named in the error: lib/broken.ex\n"
    assert message =~ "NO mutation applied"
    assert message =~ "lib/tiny.ex:"
  end

  # A change outside the mutated file can break the mutated file itself: here
  # the function it imports is gone. The error names the mutated file, but the
  # cause is outside the mutant, and every mutant of this file would be blamed.
  test "a mutated file that another file broke stops the run", %{tmp_dir: tmp_dir} do
    project = write_tiny_project!(tmp_dir, "")

    File.write!(lib_file(project), """
    defmodule Tiny do
      import Helper
      def add(a, b), do: twice(a) + b
    end
    """)

    File.write!(
      Path.join(project, "lib/helper.ex"),
      "defmodule Helper do\n  def once(x), do: x\nend\n"
    )

    assert {:error, message} = run_quietly(config!(project, "terminal", files: lib_file(project)))
    assert message =~ "Named in the error: lib/tiny.ex\n"
    assert message =~ "NO mutation applied"
  end

  # A test that halts the VM stops every run before ExUnit reports, with or
  # without the mutant. With no baseline in a plain project, nothing else would
  # notice, and every mutant would be scored invalid. The exception text it
  # prints first makes the run look like a compile error, which it is not.
  test "a test that stops the run before ExUnit reports stops the whole run",
       %{tmp_dir: tmp_dir} do
    project = write_tiny_project!(tmp_dir, "")

    File.write!(Path.join(project, "test/tiny_test.exs"), """
    defmodule TinyTest do
      use ExUnit.Case
      test "add/2" do
        assert Tiny.add(2, 3) == 5
        IO.puts("** (ArgumentError) something unrelated")
        System.halt(1)
      end
    end
    """)

    assert {:error, message} = run_quietly(config!(project, "terminal"))
    assert message =~ "stopped before ExUnit reported"
    assert message =~ "NO mutation applied"
  end

  # The mutant can break a file other than its own: a caller of a macro it
  # changed. That is still the mutant's doing, so it is invalid, and the run
  # goes on. So is a mutant that breaks its own file. Both fail a
  # --warnings-as-errors build with "size(2.0)" in a binary pattern.
  test "a mutant that breaks its own file or a caller of its macro is invalid and the run goes on",
       %{tmp_dir: tmp_dir} do
    project = write_macro_project!(tmp_dir)

    capture_io(fn ->
      assert {:ok, %{results: results}} =
               Muex.run(config!(project, "terminal", files: lib_file(project)))

      # A warning under --warnings-as-errors (or, where an Elixir version
      # rejects the size outright, a compile error) in the file with the pattern.
      own = invalid_at!(results, 2)
      assert {kind, own_output} = own.error
      assert kind in [:no_test_summary, :compile_error]
      assert own_output =~ "lib/tiny.ex"

      caller = invalid_at!(results, 3)
      assert {kind, caller_output} = caller.error
      assert kind in [:no_test_summary, :compile_error]
      assert caller_output =~ "lib/caller.ex"
      refute caller_output =~ "lib/tiny.ex:"

      assert Enum.any?(results, &(&1.result == :killed))
    end)
  end

  defp lib_file(project), do: Path.join(project, "lib/tiny.ex")

  defp run_quietly(config) do
    {result, _stderr} =
      with_io(:stderr, fn ->
        {result, _stdout} = with_io(fn -> Muex.run(config) end)
        result
      end)

    result
  end

  defp invalid_at!(results, line) do
    [result] =
      Enum.filter(
        results,
        &(&1.mutation.location.line == line and &1.mutation.description =~ "* to /")
      )

    assert result.result == :invalid
    result
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
      ]
      |> Keyword.merge(extra)

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

  # Line 2's `4 * 2` sizes a binary pattern in this file, line 3's inside a
  # macro that Caller uses in its own pattern. `* to /` makes either size a
  # float, which the compiler warns about in the file holding the pattern.
  defp write_macro_project!(tmp_dir) do
    root = Path.join(tmp_dir, "tiny")

    write_files!(root, %{
      "mix.exs" => """
      defmodule Tiny.MixProject do
        use Mix.Project

        def project,
          do: [app: :tiny, version: "0.1.0", elixir: "~> 1.15", elixirc_options: [warnings_as_errors: true]]
      end
      """,
      "lib/tiny.ex" => """
      defmodule Tiny do
        @width 4 * 2
        defmacro width, do: 2 * 4
        def first(<<x::size(@width), _::binary>>), do: x
      end
      """,
      "lib/caller.ex" => """
      defmodule Caller do
        require Tiny
        def first(<<x::size(Tiny.width()), _::binary>>), do: x
      end
      """,
      "test/test_helper.exs" => "ExUnit.start()\n",
      "test/tiny_test.exs" => """
      defmodule TinyTest do
        use ExUnit.Case
        test "first/1" do
          assert Tiny.first(<<1, 2>>) == 1
          assert Caller.first(<<1, 2>>) == 1
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
