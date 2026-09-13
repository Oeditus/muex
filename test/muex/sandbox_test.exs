defmodule Muex.SandboxTest do
  use ExUnit.Case

  import ExUnit.CaptureIO, only: [with_io: 2]

  alias Muex.Sandbox

  @project_root File.cwd!()

  describe "create_sandbox/4" do
    test "creates a sandbox directory with expected structure" do
      root = Path.join(System.tmp_dir!(), "muex_test_sandbox_#{System.system_time(:microsecond)}")

      on_exit(fn -> File.rm_rf!(root) end)

      sandbox = Sandbox.create_sandbox(root, @project_root, "test", ["test"])

      assert sandbox.root == root
      assert sandbox.project_root == @project_root

      # mix.exs should be symlinked
      assert File.exists?(Path.join(root, "mix.exs"))
      assert {:ok, _} = File.read_link(Path.join(root, "mix.exs"))

      # deps/ should be symlinked
      assert File.exists?(Path.join(root, "deps"))
      assert {:ok, _} = File.read_link(Path.join(root, "deps"))

      # lib/ should be a real directory (not a symlink) containing symlinks
      lib_dir = Path.join(root, "lib")
      assert File.dir?(lib_dir)
      # lib/ itself should NOT be a symlink
      assert {:error, _} = File.read_link(lib_dir)

      # Source files inside lib/ should be symlinks
      lib_files = Path.wildcard(Path.join([root, "lib", "**", "*.ex"]))
      assert match?([_ | _], lib_files)

      for file <- lib_files do
        assert {:ok, _target} = File.read_link(file),
               "Expected #{file} to be a symlink"
      end

      # test/ should be symlinked
      assert File.exists?(Path.join(root, "test"))

      # _build should exist
      assert File.dir?(Path.join(root, "_build"))
    end

    test "narrowing --test-paths to a single file still links test_helper.exs and support/" do
      project_root =
        Path.join(System.tmp_dir!(), "muex_test_project_#{System.system_time(:microsecond)}")

      root = Path.join(System.tmp_dir!(), "muex_test_sandbox_#{System.system_time(:microsecond)}")

      File.mkdir_p!(Path.join(project_root, "lib"))
      File.mkdir_p!(Path.join(project_root, "test/support"))
      File.mkdir_p!(Path.join(project_root, "test/fixtures"))
      File.write!(Path.join(project_root, "mix.exs"), "# fake mix.exs")
      File.write!(Path.join(project_root, "lib/foo.ex"), "defmodule Foo, do: nil")
      File.write!(Path.join(project_root, "test/test_helper.exs"), "ExUnit.start()")
      File.write!(Path.join(project_root, "test/foo_test.exs"), "# foo test")
      File.write!(Path.join(project_root, "test/support/helper.ex"), "defmodule Helper, do: nil")
      File.write!(Path.join(project_root, "test/fixtures/data.json"), "1 10")

      on_exit(fn ->
        File.rm_rf!(root)
        File.rm_rf!(project_root)
      end)

      Sandbox.create_sandbox(root, project_root, "test", ["test/foo_test.exs"])

      # The explicitly requested file is linked.
      assert File.exists?(Path.join(root, "test/foo_test.exs"))

      # The regression this PR fixes: test_helper.exs must be reachable even
      # though --test-paths named only one file inside test/, otherwise
      # `mix test` aborts before ExUnit ever starts.
      assert File.exists?(Path.join(root, "test/test_helper.exs"))

      # support/ code (e.g. shared ExUnit.CaseTemplate modules) must be
      # reachable too.
      assert File.exists?(Path.join(root, "test/support/helper.ex"))

      # Fixture directories/files in test_root must be reachable too.
      assert File.exists?(Path.join(root, "test/fixtures/data.json"))
    end

    test "narrowing --test-paths to the whole test/ directory still works" do
      project_root =
        Path.join(System.tmp_dir!(), "muex_test_project_#{System.system_time(:microsecond)}")

      root = Path.join(System.tmp_dir!(), "muex_test_sandbox_#{System.system_time(:microsecond)}")

      File.mkdir_p!(Path.join(project_root, "lib"))
      File.mkdir_p!(Path.join(project_root, "test/support"))
      File.write!(Path.join(project_root, "mix.exs"), "# fake mix.exs")
      File.write!(Path.join(project_root, "lib/foo.ex"), "defmodule Foo, do: nil")
      File.write!(Path.join(project_root, "test/test_helper.exs"), "ExUnit.start()")
      File.write!(Path.join(project_root, "test/foo_test.exs"), "# foo test")
      File.write!(Path.join(project_root, "test/support/helper.ex"), "defmodule Helper, do: nil")

      on_exit(fn ->
        File.rm_rf!(root)
        File.rm_rf!(project_root)
      end)

      Sandbox.create_sandbox(root, project_root, "test", ["test"])

      assert File.exists?(Path.join(root, "test/foo_test.exs"))
      assert File.exists?(Path.join(root, "test/test_helper.exs"))
      assert File.exists?(Path.join(root, "test/support/helper.ex"))
    end

    test "a project shape with no test_helper.exs does not raise" do
      project_root =
        Path.join(System.tmp_dir!(), "muex_test_project_#{System.system_time(:microsecond)}")

      root = Path.join(System.tmp_dir!(), "muex_test_sandbox_#{System.system_time(:microsecond)}")

      File.mkdir_p!(Path.join(project_root, "lib"))
      File.mkdir_p!(Path.join(project_root, "test"))
      File.write!(Path.join(project_root, "mix.exs"), "# fake mix.exs")
      File.write!(Path.join(project_root, "lib/foo.ex"), "defmodule Foo, do: nil")
      File.write!(Path.join(project_root, "test/foo_test.exs"), "# foo test")

      on_exit(fn ->
        File.rm_rf!(root)
        File.rm_rf!(project_root)
      end)

      sandbox = Sandbox.create_sandbox(root, project_root, "test", ["test/foo_test.exs"])

      assert sandbox.root == root
      assert File.exists?(Path.join(root, "test/foo_test.exs"))
      refute File.exists?(Path.join(root, "test/test_helper.exs"))
    end
  end

  describe "apply_mutation/4 and restore/2" do
    setup do
      root = Path.join(System.tmp_dir!(), "muex_test_sandbox_#{System.system_time(:microsecond)}")
      sandbox = Sandbox.create_sandbox(root, @project_root, "test", ["test"])
      on_exit(fn -> File.rm_rf!(root) end)
      %{sandbox: sandbox}
    end

    test "replaces a source file symlink with mutated content", %{sandbox: sandbox} do
      target_file = "lib/muex.ex"
      sandbox_path = Path.join(sandbox.root, target_file)

      # Before: should be a symlink
      assert {:ok, _} = File.read_link(sandbox_path)

      # Apply mutation
      {:ok, _precompiled} = Sandbox.apply_mutation(sandbox, target_file, "# mutated content", nil)

      # After: should be a real file with mutated content (padded with trailing
      # newlines, see "apply_mutation/4 file sizes")
      assert {:error, _} = File.read_link(sandbox_path)
      assert String.trim_trailing(File.read!(sandbox_path), "\n") == "# mutated content"

      # Original file should be untouched
      original = File.read!(Path.join(@project_root, target_file))
      refute original == "# mutated content"
    end

    test "restore recovers original content", %{sandbox: sandbox} do
      target_file = "lib/muex.ex"
      sandbox_path = Path.join(sandbox.root, target_file)

      {:ok, _precompiled} = Sandbox.apply_mutation(sandbox, target_file, "# mutated", nil)
      assert String.trim_trailing(File.read!(sandbox_path), "\n") == "# mutated"

      :ok = Sandbox.restore(sandbox, target_file)

      # Content should match original
      original = File.read!(Path.join(@project_root, target_file))
      assert File.read!(sandbox_path) == original
    end
  end

  describe "create_pool/2" do
    test "creates the requested number of sandboxes" do
      sandboxes = Sandbox.create_pool(3, project_root: @project_root, test_paths: ["test"])
      on_exit(fn -> Sandbox.cleanup(sandboxes) end)

      assert length(sandboxes) == 3

      # Each sandbox should have its own root
      roots = Enum.map(sandboxes, & &1.root)
      assert roots == Enum.uniq(roots)

      # Each should have lib/ with files
      for sandbox <- sandboxes do
        lib_files = Path.wildcard(Path.join([sandbox.root, "lib", "**", "*.ex"]))
        assert match?([_ | _], lib_files)
      end
    end
  end

  describe "cleanup/1" do
    test "removes all sandbox directories" do
      sandboxes = Sandbox.create_pool(2, project_root: @project_root, test_paths: ["test"])
      roots = Enum.map(sandboxes, & &1.root)

      for root <- roots, do: assert(File.dir?(root))

      Sandbox.cleanup(sandboxes)

      for root <- roots, do: refute(File.dir?(root))
    end

    test "handles empty list" do
      assert :ok = Sandbox.cleanup([])
    end
  end

  describe "isolation" do
    test "mutations in one sandbox don't affect another" do
      sandboxes = Sandbox.create_pool(2, project_root: @project_root, test_paths: ["test"])
      on_exit(fn -> Sandbox.cleanup(sandboxes) end)

      [sb1, sb2] = sandboxes
      target_file = "lib/muex.ex"

      # Mutate in sandbox 1
      {:ok, _precompiled} = Sandbox.apply_mutation(sb1, target_file, "# sandbox 1 mutation", nil)

      # Sandbox 2 should still have the original (via symlink)
      sb2_path = Path.join(sb2.root, target_file)
      sb2_content = File.read!(sb2_path)
      original = File.read!(Path.join(@project_root, target_file))
      assert sb2_content == original

      # Sandbox 1 should have mutated content
      sb1_path = Path.join(sb1.root, target_file)
      assert String.trim_trailing(File.read!(sb1_path), "\n") == "# sandbox 1 mutation"

      # Restore sandbox 1
      :ok = Sandbox.restore(sb1, target_file)
      assert File.read!(sb1_path) == original
    end
  end

  describe "check_targets!/2" do
    @describetag :tmp_dir

    test "refuses an umbrella file outside apps/, which the sandbox links", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "apps/a/lib"))

      assert :ok = Sandbox.check_targets!(tmp_dir, ["apps/a/lib/a.ex"])

      error =
        assert_raise Sandbox.Error, fn ->
          Sandbox.check_targets!(tmp_dir, ["apps/a/lib/a.ex", "lib/root.ex"])
        end

      assert error.message =~ "lib/root.ex"
      refute error.message =~ "apps/a/lib/a.ex"

      assert_raise Sandbox.Error, fn ->
        Sandbox.check_targets!(tmp_dir, ["apps/a/../../config/config.exs"])
      end
    end

    test "accepts any target in a plain project", %{tmp_dir: tmp_dir} do
      assert :ok = Sandbox.check_targets!(tmp_dir, ["lib/foo.ex"])
    end
  end

  # Mix treats a source as unchanged when its size matches the last compile and
  # its mtime (whole seconds) does too, or on Elixir < 1.20 is not newer. Two
  # same-size mutants written in one second were never recompiled, so every test
  # failed on the module whose .beam was deleted, and the mutant was scored
  # killed untested.
  describe "apply_mutation/4 file sizes" do
    @describetag :tmp_dir

    test "every write gets a size no compile has recorded", %{tmp_dir: tmp_dir} do
      original = "defmodule Foo do\n  def a, do: 1 + 2\nend\n"
      project_root = Path.join(tmp_dir, "project")
      File.mkdir_p!(Path.join(project_root, "lib"))
      File.write!(Path.join(project_root, "mix.exs"), "# fake mix.exs")
      File.write!(Path.join(project_root, "lib/foo.ex"), original)

      sandbox = Sandbox.create_sandbox(Path.join(tmp_dir, "sandbox"), project_root, "test", [])
      written = Path.join(sandbox.root, "lib/foo.ex")

      # Same byte size as each other and as the original: the case Mix could not
      # tell apart.
      sizes =
        for mutant <- [
              "defmodule Foo do\n  def a, do: 1 - 2\nend\n",
              "defmodule Foo do\n  def a, do: 1 * 2\nend\n"
            ] do
          assert {:ok, _} = Sandbox.apply_mutation(sandbox, "lib/foo.ex", mutant, nil)
          contents = File.read!(written)
          # Only trailing newlines were added: no code, no line moved.
          assert String.trim_trailing(contents, "\n") == String.trim_trailing(mutant, "\n")
          :ok = Sandbox.restore(sandbox, "lib/foo.ex")
          byte_size(contents)
        end

      assert [first, second] = sizes
      assert first != second
      assert first != byte_size(original) and second != byte_size(original)
      # The real project was not touched.
      assert File.read!(Path.join(project_root, "lib/foo.ex")) == original
    end
  end

  describe "umbrella sandboxes" do
    @describetag :tmp_dir

    # apps/b depends on apps/a in_umbrella. Linking apps one by one sends b's
    # `path: "../a"` to the real project while the root sees the sandbox copy,
    # so the sandbox cannot compile. A cloned apps/ keeps both paths inside.
    setup %{tmp_dir: tmp_dir} do
      project_root = Path.join(tmp_dir, "umbrella")

      files = %{
        "mix.exs" => """
        defmodule Umbrella.MixProject do
          use Mix.Project
          def project, do: [apps_path: "apps", version: "0.1.0", deps: []]
        end
        """,
        "config/config.exs" => "import Config\n",
        "apps/a/mix.exs" => app_mix_exs(:a, "A", []),
        "apps/a/lib/a.ex" => "defmodule A do\n  def one, do: 1\nend\n",
        "apps/b/mix.exs" => app_mix_exs(:b, "B", [{:a, in_umbrella: true}]),
        "apps/b/lib/b.ex" => "defmodule B do\n  def two, do: A.one() + 1\nend\n"
      }

      for {path, content} <- files do
        full = Path.join(project_root, path)
        File.mkdir_p!(Path.dirname(full))
        File.write!(full, content)
      end

      File.write!(Path.join(tmp_dir, "beside.txt"), "a file next to the umbrella")

      %{project_root: project_root}
    end

    test "clone apps/ and compile in_umbrella deps without touching the project",
         %{project_root: project_root} do
      [sandbox] = warm_pool(project_root)
      on_exit(fn -> Sandbox.cleanup([sandbox]) end)

      assert Path.basename(sandbox.root) == "umbrella"
      assert {:error, _} = File.read_link(Path.join(sandbox.root, "apps"))
      assert {:ok, _} = File.read_link(Path.join(sandbox.root, "config"))
      assert File.exists?(Path.join(sandbox.root, "../beside.txt"))

      # The warm-up compiled both apps inside the sandbox...
      assert File.exists?(Path.join(sandbox.root, "_build/test/lib/b/ebin/Elixir.B.beam"))
      # ...and wrote nothing into the real project.
      refute File.exists?(Path.join(project_root, "_build"))
    end

    test "never writes a mutant through a link", %{project_root: project_root} do
      [sandbox] = warm_pool(project_root)
      on_exit(fn -> Sandbox.cleanup([sandbox]) end)

      real = Path.join(project_root, "config/config.exs")
      before = File.read!(real)

      assert {:error, {:outside_sandbox, "config/config.exs"}} =
               Sandbox.apply_mutation(sandbox, "config/config.exs", "# mutant", nil)

      assert_raise Sandbox.Error, fn -> Sandbox.restore(sandbox, "config/config.exs") end
      assert File.read!(real) == before
    end

    test "removes the pool when a sandbox does not compile", %{project_root: project_root} do
      File.write!(Path.join(project_root, "apps/a/lib/broken.ex"), "defmodule Broken do\n")

      {error, _stderr} =
        with_io(:stderr, fn ->
          assert_raise Sandbox.Error, ~r/failed to compile/, fn ->
            Sandbox.create_pool(1, project_root: project_root, test_paths: [])
          end
        end)

      [_, root] = Regex.run(~r/sandbox (\S+) failed to compile/, error.message)
      pool_base = root |> Path.dirname() |> Path.dirname()
      assert String.starts_with?(Path.basename(pool_base), "muex_sandboxes_")
      refute File.exists?(pool_base)
    end
  end

  # Warm-up progress goes to stderr, so it cannot corrupt `--format json`.
  defp warm_pool(project_root) do
    {sandboxes, stderr} =
      with_io(:stderr, fn ->
        Sandbox.create_pool(1, project_root: project_root, test_paths: [])
      end)

    assert stderr =~ "muex: warmed worker_1/umbrella"
    sandboxes
  end

  defp app_mix_exs(app, name, deps) do
    """
    defmodule #{name}.MixProject do
      use Mix.Project

      def project do
        [
          app: #{inspect(app)},
          version: "0.1.0",
          build_path: "../../_build",
          config_path: "../../config/config.exs",
          deps_path: "../../deps",
          lockfile: "../../mix.lock",
          deps: #{inspect(deps)}
        ]
      end
    end
    """
  end
end
