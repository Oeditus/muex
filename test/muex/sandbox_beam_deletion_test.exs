defmodule Muex.SandboxBeamDeletionTest do
  @moduledoc """
  A mutation must never remove compiled modules from the project itself.

  Every app under a fresh sandbox's `_build` is a symlink into the project's
  real build directory. Deleting a beam by wildcard walks through that symlink,
  and because the sources have not changed Mix does not rebuild what goes
  missing — the next `mix test` fails to start the application.
  """
  use ExUnit.Case, async: false

  alias Muex.Sandbox

  @app "demo_app"
  @module Elixir.Demo.Thing

  setup do
    unique = System.unique_integer([:positive, :monotonic])
    base = Path.join(System.tmp_dir!(), "muex_beam_test_#{unique}")
    project = Path.join(base, "project")
    sandbox_root = Path.join(base, "sandbox")

    on_exit(fn -> File.rm_rf!(base) end)

    File.mkdir_p!(Path.join(project, "lib"))
    File.mkdir_p!(Path.join(project, "tools"))
    File.mkdir_p!(Path.join(project, "deps"))
    File.write!(Path.join(project, "mix.exs"), "# not compiled by these tests\n")
    File.write!(Path.join([project, "lib", "thing.ex"]), "defmodule Demo.Thing do\nend\n")
    File.write!(Path.join([project, "tools", "helper.ex"]), "defmodule Demo.Helper do\nend\n")

    %{base: base, project: project, sandbox_root: sandbox_root}
  end

  defp build_app(project, env, beams) do
    ebin = Path.join([project, "_build", env, "lib", @app, "ebin"])
    File.mkdir_p!(ebin)
    File.mkdir_p!(Path.join([project, "_build", env, "lib", @app, ".mix"]))
    File.write!(Path.join([project, "_build", env, "lib", @app, ".mix", "compile.elixir"]), "")
    for beam <- beams, do: File.write!(Path.join(ebin, beam), "stale")
    ebin
  end

  defp project_beam(project, env, name),
    do: Path.join([project, "_build", env, "lib", @app, "ebin", name])

  test "leaves the project's beams alone when the app build is still a symlink",
       %{project: project, sandbox_root: root} do
    beam = "#{@module}.beam"
    build_app(project, "test", [beam])

    sandbox = Sandbox.create_sandbox(root, project, "test", [])

    # Force the situation the bug needs: the sandbox's app build is a symlink
    # into the project, exactly as create_sandbox leaves it before any copy.
    app_build = Path.join([root, "_build", "test", "lib", @app])
    assert {:ok, _} = File.read_link(app_build)

    assert {:ok, _} =
             Sandbox.apply_mutation(
               sandbox,
               "lib/thing.ex",
               "defmodule Demo.Thing do\n  def x, do: 1\nend\n",
               @module
             )

    assert File.exists?(project_beam(project, "test", beam)),
           "the project's compiled module was deleted through the sandbox symlink"
  end

  test "removes the beam from its own copy, not from the project",
       %{project: project, sandbox_root: root} do
    beam = "#{@module}.beam"
    build_app(project, "test", [beam])

    sandbox = Sandbox.create_sandbox(root, project, "test", [])

    assert {:ok, _} =
             Sandbox.apply_mutation(
               sandbox,
               "lib/thing.ex",
               "defmodule Demo.Thing do\n  def x, do: 1\nend\n",
               @module
             )

    sandbox_beam = Path.join([root, "_build", "test", "lib", @app, "ebin", beam])

    refute File.exists?(sandbox_beam), "the sandbox's own stale beam should be gone"
    assert File.exists?(project_beam(project, "test", beam))
  end

  test "handles sources compiled from outside lib/", %{project: project, sandbox_root: root} do
    beam = "#{Elixir.Demo.Helper}.beam"
    build_app(project, "test", [beam])

    sandbox = Sandbox.create_sandbox(root, project, "test", [])
    File.mkdir_p!(Path.join(root, "tools"))
    File.write!(Path.join([root, "tools", "helper.ex"]), "defmodule Demo.Helper do\nend\n")

    assert {:ok, _} =
             Sandbox.apply_mutation(
               sandbox,
               "tools/helper.ex",
               "defmodule Demo.Helper do\n  def x, do: 1\nend\n",
               Elixir.Demo.Helper
             )

    assert File.exists?(project_beam(project, "test", beam)),
           "elixirc_paths accepts any directory, and those files must be handled too"
  end

  test "uses the sandbox's build env rather than assuming test",
       %{project: project, sandbox_root: root} do
    beam = "#{@module}.beam"
    build_app(project, "dev", [beam])

    sandbox = Sandbox.create_sandbox(root, project, "dev", [])

    assert {:ok, _} =
             Sandbox.apply_mutation(
               sandbox,
               "lib/thing.ex",
               "defmodule Demo.Thing do\n  def x, do: 1\nend\n",
               @module
             )

    assert File.exists?(project_beam(project, "dev", beam))
    refute File.exists?(Path.join([root, "_build", "dev", "lib", @app, "ebin", beam]))
  end

  test "takes the build copy from MIX_BUILD_ROOT when it is set",
       %{base: base, project: project, sandbox_root: root} do
    beam = "#{@module}.beam"

    # The project also has a stale <project>/_build from an earlier run; the
    # run in progress is using the other root, and that is the one that counts.
    build_app(project, "test", [beam])

    build_root = Path.join(base, "elsewhere")
    ebin = Path.join([build_root, "test", "lib", @app, "ebin"])
    File.mkdir_p!(ebin)
    File.mkdir_p!(Path.join([build_root, "test", "lib", @app, ".mix"]))
    File.write!(Path.join([build_root, "test", "lib", @app, ".mix", "compile.elixir"]), "")
    File.write!(Path.join(ebin, beam), "from the build root actually in use")

    # Only the root in use has this one. If the copy came from the stale
    # <project>/_build instead, it will be missing from the sandbox.
    File.write!(Path.join(ebin, "Elixir.Demo.OnlyHere.beam"), "marker")

    System.put_env("MIX_BUILD_ROOT", build_root)
    on_exit(fn -> System.delete_env("MIX_BUILD_ROOT") end)

    sandbox = Sandbox.create_sandbox(root, project, "test", [])

    assert {:ok, _} =
             Sandbox.apply_mutation(
               sandbox,
               "lib/thing.ex",
               "defmodule Demo.Thing do\n  def x, do: 1\nend\n",
               @module
             )

    sandbox_app = Path.join([root, "_build", "test", "lib", @app])

    assert File.dir?(sandbox_app) and match?({:error, _}, File.read_link(sandbox_app)),
           "the sandbox should hold a real copy rather than a symlink"

    assert File.exists?(Path.join([sandbox_app, "ebin", "Elixir.Demo.OnlyHere.beam"])),
           "the copy was taken from <project>/_build, not from MIX_BUILD_ROOT"

    assert File.exists?(Path.join(ebin, beam)),
           "the build root in use must not be mutated through a symlink"
  end
end
