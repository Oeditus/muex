defmodule Muex.MixBootstrapTest do
  use ExUnit.Case, async: false

  alias Muex.MixBootstrap

  @moduletag :tmp_dir

  setup do
    # Every test loads a project into the global Mix.ProjectStack; clear it
    # afterwards so one test's project cannot answer for the next.
    on_exit(fn -> Mix.ProjectStack.clear_stack() end)
  end

  describe "find_project_file/1" do
    test "finds the mix.exs in the given directory", %{tmp_dir: tmp_dir} do
      project_file = Path.join(tmp_dir, "mix.exs")
      File.write!(project_file, "")

      assert MixBootstrap.find_project_file(tmp_dir) == project_file
    end

    test "walks up to the nearest mix.exs", %{tmp_dir: tmp_dir} do
      project_file = Path.join(tmp_dir, "mix.exs")
      File.write!(project_file, "")
      nested = Path.join([tmp_dir, "lib", "deeply", "nested"])
      File.mkdir_p!(nested)

      assert MixBootstrap.find_project_file(nested) == project_file
    end

    test "stops at the filesystem root when there is no mix.exs", %{tmp_dir: tmp_dir} do
      # The test's own directory needs a mix.exs, or the walk would climb out of
      # it and find the one of the project muex itself is tested in.
      project_file = Path.join(tmp_dir, "mix.exs")
      File.write!(project_file, "")

      assert MixBootstrap.find_project_file(Path.join(tmp_dir, "lib")) == project_file
    end
  end

  describe "start/1" do
    test "starts Mix and evaluates the project's mix.exs", %{tmp_dir: tmp_dir} do
      project = write_project!(tmp_dir, :bootstrap_probe)

      assert :ok = MixBootstrap.start(project.file)
      assert Mix.Project.get() == project.module
      assert Mix.Project.config()[:app] == :bootstrap_probe
      assert Path.expand(Mix.Project.project_file()) == Path.expand(project.file)
    end

    test "starts Mix without a project when there is no mix.exs", %{tmp_dir: tmp_dir} do
      assert :ok = MixBootstrap.start(Path.join(tmp_dir, "missing.exs"))
      assert Mix.Project.get() == nil
    end
  end

  describe "load_project/1" do
    test "loads the project at or above the given directory", %{tmp_dir: tmp_dir} do
      project = write_project!(tmp_dir, :loaded_probe)
      nested = Path.join(tmp_dir, "lib")
      File.mkdir_p!(nested)

      assert :ok = MixBootstrap.load_project(nested)
      assert Mix.Project.get() == project.module
      assert Mix.Project.config()[:app] == :loaded_probe
    end

    test "reports a missing project instead of crashing" do
      # A directory with no mix.exs anywhere above it. The test's own directory
      # cannot be used: it sits inside the muex project, whose mix.exs would be
      # found by walking up.
      dir = Path.join(System.tmp_dir!(), "muex_no_project_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf(dir) end)

      assert {:error, {:no_project, reported}} = MixBootstrap.load_project(dir)
      assert reported == Path.expand(dir)
    end

    test "reports a mix.exs that raises", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "mix.exs"), """
      defmodule #{module_name(tmp_dir)} do
        use Mix.Project
        def project, do: raise("boom")
      end
      """)

      assert {:error, {:load_failed, _file, exception}} = MixBootstrap.load_project(tmp_dir)
      assert Exception.message(exception) =~ "boom"
    end
  end

  describe "format_error/1" do
    test "explains where Mix comes from" do
      message = MixBootstrap.format_error({:no_mix, "no `elixir` executable was found on PATH"})

      assert message =~ "Mix is not available"
      assert message =~ "no `elixir` executable was found on PATH"
      assert message =~ "PATH"
    end

    test "names the directory searched for mix.exs" do
      message = MixBootstrap.format_error({:no_project, "/some/dir"})

      assert message =~ "No mix.exs found in /some/dir"
      assert message =~ "root of an Elixir project"
    end

    test "includes the exception raised while loading mix.exs" do
      exception = %RuntimeError{message: "boom"}
      message = MixBootstrap.format_error({:load_failed, "/p/mix.exs", exception})

      assert message =~ "Could not load /p/mix.exs"
      assert message =~ "boom"
    end
  end

  # A minimal but real project: `mix.exs` defines the project, and `lib/` holds
  # one module, so `loadpaths` and `compile` have something to do. Mix refuses
  # two projects with the same module name, so each gets its own.
  defp write_project!(dir, app) do
    module = module_name(dir)

    File.write!(Path.join(dir, "mix.exs"), """
    defmodule #{module} do
      use Mix.Project

      def project do
        [app: #{inspect(app)}, version: "0.1.0", elixir: "~> 1.14"]
      end
    end
    """)

    File.mkdir_p!(Path.join(dir, "lib"))

    File.write!(
      Path.join(dir, "lib/probe.ex"),
      "defmodule Probe do\n  def hello, do: :world\nend\n"
    )

    %{file: Path.join(dir, "mix.exs"), module: Module.concat([module])}
  end

  defp module_name(dir) do
    "Probe#{dir |> Path.basename() |> then(&:erlang.phash2/1)}.MixProject"
  end
end
