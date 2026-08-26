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

  # A compiled dependency: the same `.mix/compile.elixir` marker the app under
  # test has, which is what makes counting those markers ambiguous.
  defp build_dep(project, env, name) do
    File.mkdir_p!(Path.join([project, "_build", env, "lib", name, "ebin"]))
    File.mkdir_p!(Path.join([project, "_build", env, "lib", name, ".mix"]))
    File.write!(Path.join([project, "_build", env, "lib", name, ".mix", "compile.elixir"]), "")
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

  # A project with dependencies has more than one app under `_build/<env>/lib`,
  # which is the normal case rather than an exotic one — muex's own install line
  # (`only: [:dev, :test]`) puts muex and jason there. Counting build
  # directories cannot name the app under test in that situation; the app name
  # has to come from the project itself.
  test "resolves the app name when dependencies are built alongside it",
       %{project: project, sandbox_root: root} do
    beam = "#{@module}.beam"
    build_app(project, "test", [beam])
    build_dep(project, "test", "jason")
    build_dep(project, "test", "muex")

    write_mix_exs(project, "[app: @app, version: \"0.1.0\", elixir: \"~> 1.14\"]")

    assert_own_build_copy(project, root, beam)
  end

  # `:app` is not unique to the project's own options: `escript:` takes one too.
  # Reading the first `app:` found anywhere in `def project` would answer with
  # that one whenever it comes first.
  test "reads the project's own app name, not a nested one",
       %{project: project, sandbox_root: root} do
    beam = "#{@module}.beam"
    build_app(project, "test", [beam])
    build_dep(project, "test", "jason")
    build_dep(project, "test", "muex")

    write_mix_exs(project, """
    [
            escript: [main_module: DemoApp.CLI, app: :something_else],
            app: @app,
            version: "0.1.0"
          ]\
    """)

    assert_own_build_copy(project, root, beam)
  end

  defp write_mix_exs(project, options) do
    File.write!(Path.join(project, "mix.exs"), """
    defmodule DemoApp.MixProject do
      use Mix.Project

      @app :#{@app}

      def project do
        #{options}
      end
    end
    """)
  end

  defp assert_own_build_copy(project, root, beam) do
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
           "the sandbox must hold its own copy; a symlink means every worker " <>
             "compiles into the project's real build directory"

    refute File.exists?(Path.join([sandbox_app, "ebin", beam])),
           "the sandbox's own stale beam should be gone"

    assert File.exists?(project_beam(project, "test", beam)),
           "the project's compiled module must survive"
  end
end
