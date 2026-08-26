defmodule Muex.SandboxTest do
  use ExUnit.Case

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

      # After: should be a real file with mutated content
      assert {:error, _} = File.read_link(sandbox_path)
      assert File.read!(sandbox_path) == "# mutated content"

      # Original file should be untouched
      original = File.read!(Path.join(@project_root, target_file))
      refute original == "# mutated content"
    end

    test "restore recovers original content", %{sandbox: sandbox} do
      target_file = "lib/muex.ex"
      sandbox_path = Path.join(sandbox.root, target_file)

      {:ok, _precompiled} = Sandbox.apply_mutation(sandbox, target_file, "# mutated", nil)
      assert File.read!(sandbox_path) == "# mutated"

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
      assert File.read!(sb1_path) == "# sandbox 1 mutation"

      # Restore sandbox 1
      :ok = Sandbox.restore(sb1, target_file)
      assert File.read!(sb1_path) == original
    end
  end
end
