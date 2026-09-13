defmodule Muex.Sandbox do
  @moduledoc """
  Creates isolated working directories for parallel mutation testing.

  Each sandbox mirrors the project structure using symlinks, with its own
  `_build` directory and a copy of the single mutated source file. This
  allows multiple `mix test` processes to run simultaneously without
  seeing each other's mutations.

  Supports both standard Mix projects and umbrella projects.

  ## Structure (umbrella)

      worker_N/
      ├── <siblings of the project dir>  → symlink (all but .git)
      └── <project dir name>/
          ├── mix.exs, config/, deps/, ...  → symlink to project
          │                   (every top-level entry except apps/ and _build/)
          ├── apps/          → copy-on-write clone of the project's apps/
          │   └── my_app/lib/mutated.ex → overwritten with the mutated source
          └── _build/<env>/  → copy-on-write clone, compiled once when the
                               pool is created (see create_pool/2)
  """

  defmodule Error do
    @moduledoc """
    Raised when a run cannot give a trustworthy verdict: a sandbox does not
    compile, the selected tests fail with no mutation applied, a target file
    is not private to the sandbox, or a mutant has no test to judge it.
    `mix muex` reports the reason and scores nothing.
    """
    defexception [:message]
  end

  @type sandbox :: %{
          required(:root) => Path.t(),
          required(:project_root) => Path.t(),
          required(:build_env) => String.t(),
          optional(:base) => Path.t()
        }

  @doc """
  Creates a pool of reusable sandbox directories.

  Returns a list of sandbox structs that can be checked out by workers.
  """
  @spec create_pool(non_neg_integer(), keyword()) :: [sandbox()]
  def create_pool(count, opts \\ []) do
    project_root = Keyword.get(opts, :project_root, File.cwd!())
    build_env = Keyword.get(opts, :build_env, "test")
    test_paths = Keyword.get(opts, :test_paths, ["test"])

    unique = System.unique_integer([:positive, :monotonic])

    base_dir =
      Path.join(System.tmp_dir!(), "muex_sandboxes_#{System.system_time(:millisecond)}_#{unique}")

    File.mkdir_p!(base_dir)

    # Whatever fails while the pool is built or warmed (a cp error, a compile
    # error, anything), the partial tree goes with it: the caller has no
    # sandbox list yet to clean up.
    try do
      build_pool!(count, base_dir, project_root, build_env, test_paths)
    rescue
      e ->
        File.rm_rf(base_dir)
        reraise e, __STACKTRACE__
    end
  end

  defp build_pool!(count, base_dir, project_root, build_env, test_paths) do
    sandboxes =
      for i <- 1..count do
        worker_dir = Path.join(base_dir, "worker_#{i}")

        if umbrella?(project_root) do
          # The umbrella lands under its own directory name, beside links to
          # everything next to it. See link_project_siblings/2.
          root = Path.join(worker_dir, Path.basename(project_root))
          sandbox = create_sandbox(root, project_root, build_env, test_paths)
          link_project_siblings(worker_dir, project_root)
          Map.put(sandbox, :base, base_dir)
        else
          worker_dir
          |> create_sandbox(project_root, build_env, test_paths)
          |> Map.put(:base, base_dir)
        end
      end

    # Compile every umbrella sandbox once, before the first mutant, so that
    # compile is not charged to the per-mutant timeout.
    if umbrella?(project_root) do
      warm_up!(sandboxes, base_dir)
    end

    sandboxes
  end

  @doc """
  Raises `Muex.Sandbox.Error` if any file cannot be mutated safely.

  In an umbrella sandbox only `apps/` is a private copy; every other
  top-level entry is a link to the real project. A mutant of `lib/foo.ex` or
  `config/x.exs` would be written through that link into the real file, and
  `restore/2` would then delete it. Such targets are refused before any
  sandbox exists. Outside an umbrella this always returns `:ok`.
  """
  @spec check_targets!(Path.t(), [Path.t()]) :: :ok
  def check_targets!(project_root, files) do
    if umbrella?(project_root) do
      outside =
        Enum.reject(files, fn file ->
          match?(["apps", _app, _ | _], Path.split(Path.relative_to(file, project_root))) and
            ".." not in Path.split(file)
        end)

      if outside != [] do
        raise Error, """
        muex: in an umbrella only files under apps/<app>/ can be mutated; these
        are outside it, and the sandbox shares them with the real project:
        #{Enum.join(outside, "\n")}
        """
      end
    end

    :ok
  end

  # A second guard, for apply_mutation/4 and restore/2: the target and every
  # directory between it and the sandbox root must be real entries of the
  # sandbox, never a link out of it. A file that is itself a link (the
  # plain-project layout) is fine: File.rm/1 removes the link, not its target.
  defp private_path?(sandbox, original_path) do
    root = Path.expand(sandbox.root)
    target = Path.expand(original_path, root)

    String.starts_with?(target, root <> "/") and
      target
      |> Path.dirname()
      |> Path.relative_to(root)
      |> Path.split()
      |> Enum.scan(&Path.join(&2, &1))
      |> Enum.all?(fn rel ->
        not match?({:ok, %File.Stat{type: :symlink}}, File.lstat(Path.join(root, rel)))
      end)
  end

  # Tests may read files beside the Mix project, not only inside it: an
  # umbrella kept in a subdirectory of a repository often has tests that read
  # `../some_dir/file`, or climb to the repository root and come back down
  # through the umbrella's own directory name. In a bare sandbox those paths
  # are missing, the test fails on every run, and that failure "kills" every
  # mutant it judges. So the sandbox's parent mirrors the project's parent:
  # everything there is linked except `.git`, so nothing run in a sandbox can
  # reach the real git index.
  defp link_project_siblings(worker_dir, project_root) do
    parent = Path.dirname(project_root)
    own = Path.basename(project_root)

    parent
    |> File.ls!()
    |> Enum.reject(&(&1 in [own, ".git"]))
    |> Enum.each(&safe_symlink(Path.join(parent, &1), Path.join(worker_dir, &1)))
  end

  @doc """
  Creates a single sandbox directory mirroring the project.
  """
  @spec create_sandbox(Path.t(), Path.t(), String.t(), [String.t()]) :: sandbox()
  def create_sandbox(root, project_root, build_env, test_paths) do
    File.mkdir_p!(root)

    if umbrella?(project_root) do
      # A private clone of the whole umbrella. See create_umbrella_sandbox/3.
      create_umbrella_sandbox(root, project_root, build_env)
      link_test_paths(root, project_root, test_paths)
    else
      create_project_sandbox(root, project_root, build_env, test_paths)
    end

    %{root: root, project_root: project_root, build_env: build_env}
  end

  @doc false
  @spec umbrella?(Path.t()) :: boolean()
  def umbrella?(project_root), do: File.dir?(Path.join(project_root, "apps"))

  defp create_project_sandbox(root, project_root, build_env, test_paths) do
    # Symlink top-level files
    symlink_top_level(root, project_root)

    mirror_source_tree(root, project_root, "lib")

    # Symlink test directories (for explicit --test-paths)
    link_test_paths(root, project_root, test_paths)

    # Symlink deps/ (shared, read-only)
    safe_symlink(Path.join(project_root, "deps"), Path.join(root, "deps"))

    # Setup _build: symlink everything, deep copy nothing initially.
    # apply_mutation/4 handles deep-copying the specific app's build
    # artifacts on demand.
    setup_build_dir(root, project_root, build_env)
  end

  # Why the umbrella is cloned rather than linked app by app: an app that is a
  # directory symlink resolves its in_umbrella deps (`path: "../sibling"`)
  # through the link to the REAL project, while the sandbox root sees
  # `sandbox/apps/sibling`. Mix then reports the root "overriding a child
  # dependency", marks every dep as not locked, and under `--no-deps-check`
  # loads no dep code paths at all, so every mutant comes back :invalid. And a
  # `_build` entry that is a symlink lets a recompile write into the real
  # build.
  #
  # So everything that is compiled or written is a private copy-on-write
  # clone (all of `apps/` and all of `_build/<env>`), and every other
  # top-level entry is linked, so paths the umbrella reads outside `apps/`
  # (a native path dependency, say) resolve. `deps/` stays a link: it is only
  # read.
  defp create_umbrella_sandbox(root, project_root, build_env) do
    build_root = project_build_root(project_root)

    project_root
    |> File.ls!()
    |> Enum.reject(&(&1 in ["apps", "_build"] or Path.join(project_root, &1) == build_root))
    |> Enum.each(&safe_symlink(Path.join(project_root, &1), Path.join(root, &1)))

    clone_tree!(Path.join(project_root, "apps"), Path.join(root, "apps"))

    source_build = Path.join(build_root, build_env)
    target_build = Path.join([root, "_build", build_env])
    File.mkdir_p!(Path.dirname(target_build))

    if File.dir?(source_build) do
      clone_tree!(source_build, target_build)
    else
      File.mkdir_p!(Path.join(target_build, "lib"))
    end
  end

  # Copy-on-write clone (where the filesystem supports it) that keeps
  # modification times, so build tools do not see every file as just changed.
  defp clone_tree!(source, target) do
    case :os.type() do
      {:unix, :darwin} ->
        cp!(["-Rcp", source, target])

      {:unix, _} ->
        cp!(["-R", "--reflink=auto", "--preserve=mode,timestamps", source, target])

      _ ->
        File.cp_r!(source, target)
        :ok
    end
  end

  defp cp!(args) do
    case System.cmd("cp", args, stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {output, status} ->
        raise "muex: cp #{Enum.join(args, " ")} failed (exit #{status}): #{output}"
    end
  end

  # A cloned build sits at a new absolute path, so its first `mix compile`
  # rebuilds the whole umbrella (native code included). Left to the first
  # mutant's `mix test`, that compile runs inside the per-mutant timeout and is
  # killed. Compile each sandbox here instead, one at a time, because each of
  # these compiles already uses every core.
  #
  # A sandbox that will not compile would turn every mutant :invalid, which
  # reads as a score. Raise instead, with the compiler's output; create_pool/2
  # removes the tree. Progress goes to stderr so `--format json` output stays
  # parseable.
  defp warm_up!(sandboxes, base_dir) do
    Enum.each(sandboxes, fn sandbox ->
      started = System.monotonic_time(:millisecond)

      {output, status} =
        System.cmd("mix", ["compile"],
          cd: sandbox.root,
          env: [{"MIX_ENV", sandbox.build_env}],
          stderr_to_stdout: true
        )

      elapsed = System.monotonic_time(:millisecond) - started

      IO.puts(
        :stderr,
        "muex: warmed #{Path.relative_to(sandbox.root, base_dir)} in #{elapsed} ms"
      )

      if status != 0 do
        raise Error, """
        muex: sandbox #{sandbox.root} failed to compile (exit #{status}); no mutant can run.
        #{output}
        """
      end
    end)
  end

  @doc """
  Applies a mutation to a sandbox by writing the mutated source to the
  sandbox's copy of the file, and deleting the stale beam so the child
  `mix test` process recompiles it.

  Returns `{:ok, false}` on success (the child always recompiles), or
  `{:error, reason}`.
  """
  @spec apply_mutation(sandbox(), Path.t(), String.t(), atom() | nil) ::
          {:ok, boolean()} | {:error, term()}
  def apply_mutation(sandbox, original_path, mutated_source, module_name) do
    sandbox_path = Path.join(sandbox.root, original_path)

    # For umbrella projects: ensure the app containing the mutated file
    # has been mirrored (symlink replaced with file-level copies) so we
    # can swap individual source files.
    ensure_app_mirrored_for_file(sandbox, original_path)

    ensure_path_mirrored_for_file(sandbox, original_path)

    # Ensure the mutated app's build dir is a real copy (not a symlink)
    # so this sandbox can recompile independently.
    ensure_build_copy_for_file(sandbox, original_path)

    # Never write through a link into the real project (see check_targets!/2).
    if private_path?(sandbox, original_path) do
      write_mutant(sandbox, sandbox_path, original_path, mutated_source, module_name)
    else
      {:error, {:outside_sandbox, original_path}}
    end
  end

  @managed_top_level ~w(lib test spec deps _build apps config priv .git)

  defp ensure_path_mirrored_for_file(sandbox, original_path) do
    dirs = original_path |> Path.dirname() |> Path.split()

    case dirs do
      [first | _] when first in @managed_top_level -> :ok
      _ -> mirror_symlinked_dirs(dirs, sandbox.root)
    end
  end

  defp mirror_symlinked_dirs([], _root), do: :ok

  defp mirror_symlinked_dirs([dir | rest], root) do
    path = Path.join(root, dir)

    case File.lstat(path) do
      {:ok, %File.Stat{type: :symlink}} ->
        {:ok, target} = File.read_link(path)
        target = if Path.type(target) == :absolute, do: target, else: Path.expand(target, root)
        File.rm(path)
        File.mkdir_p!(path)

        target
        |> File.ls!()
        |> Enum.each(&safe_symlink(Path.join(target, &1), Path.join(path, &1)))

      {:ok, %File.Stat{type: :directory}} ->
        mirror_symlinked_dirs(rest, path)

      _ ->
        :ok
    end
  end

  defp write_mutant(sandbox, sandbox_path, original_path, mutated_source, module_name) do
    # Remove the symlink and write the mutated source as a real file
    File.rm(sandbox_path)

    case File.write(sandbox_path, pad_to_unseen_size(mutated_source, sandbox, original_path)) do
      :ok ->
        # Delete the stale .beam so the child `mix test` process detects
        # the source change and recompiles the module. Pre-compiling via
        # Code.compile_string in the parent VM is not viable: modules with
        # compile-time dependencies (use, import, structs) fail, and
        # successful compilations pollute the parent's module state.
        if module_name, do: remove_stale_beam(sandbox, original_path, module_name)

        {:ok, false}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Mix recompiles a source only when its size differs from the last compile, or
  # its mtime (whole seconds) does and then only if the .beam is missing or the
  # content changed; before Elixir 1.20 the mtime must also be newer. Two mutants
  # of one file with the same byte size, written within one second, looked
  # unchanged: nothing recompiled, the module whose .beam was deleted did not
  # exist, every test failed, and the mutant was scored killed untested.
  #
  # Size is the one check every Elixir version makes first, so trailing newlines
  # give each write a size no compile has recorded: larger than the original's,
  # and never used twice. They add no code and move no line.
  defp pad_to_unseen_size(source, sandbox, original_path) do
    %File.Stat{size: original_size} = File.stat!(Path.join(sandbox.project_root, original_path))
    target = 2 * original_size + 4096 + System.unique_integer([:positive, :monotonic])
    source <> String.duplicate("\n", max(target - byte_size(source), 1))
  end

  @doc """
  Restores a sandbox after a mutation by copying the original source file
  back over the mutated copy.
  """
  @spec restore(sandbox(), Path.t()) :: :ok
  def restore(sandbox, original_path) do
    sandbox_path = Path.join(sandbox.root, original_path)
    project_path = Path.join(sandbox.project_root, original_path)

    # The rm below would delete the REAL file if the path ran through a link.
    unless private_path?(sandbox, original_path) do
      raise Error, "muex: refusing to restore #{original_path}: it is not private to the sandbox"
    end

    # Copy the original source back over the mutated file.
    # (The app dir is a COW copy, not symlinks, so we overwrite in place.)
    File.rm(sandbox_path)
    File.cp!(project_path, sandbox_path)

    :ok
  end

  @doc """
  Cleans up all sandbox directories.
  """
  @spec cleanup([sandbox()]) :: :ok
  def cleanup(sandboxes) do
    case sandboxes do
      [%{root: first_root} = first | _] ->
        # An umbrella sandbox's root is one level deeper than the pool's base
        # directory, so use the base create_pool/2 recorded.
        base_dir = Map.get(first, :base, Path.dirname(first_root))
        File.rm_rf!(base_dir)

      [] ->
        :ok
    end

    :ok
  end

  # -- Private helpers --

  defp symlink_top_level(root, project_root) do
    top_level_files = ~w(mix.exs mix.lock .formatter.exs .credo.exs)

    for file <- top_level_files do
      source = Path.join(project_root, file)

      if File.exists?(source) do
        safe_symlink(source, Path.join(root, file))
      end
    end

    managed = ~w(lib test spec deps _build .git config priv)

    project_root
    |> File.ls!()
    |> Enum.filter(fn entry ->
      entry not in managed and File.dir?(Path.join(project_root, entry))
    end)
    |> Enum.each(fn dir ->
      safe_symlink(Path.join(project_root, dir), Path.join(root, dir))
    end)

    for dir <- ~w(config priv) do
      source = Path.join(project_root, dir)

      if File.dir?(source) do
        safe_symlink(source, Path.join(root, dir))
      end
    end
  end

  # Replace an app's directory symlink with a COW copy so that individual
  # source files can be overwritten with mutated copies. Using deep_copy
  # (cp -Rc on macOS) is much faster than creating thousands of symlinks.
  defp ensure_app_mirrored(sandbox, app_name) do
    app_target = Path.join([sandbox.root, "apps", app_name])
    app_source = Path.join([sandbox.project_root, "apps", app_name])

    case File.read_link(app_target) do
      {:ok, _link_target} ->
        File.rm!(app_target)
        deep_copy(app_source, app_target)

      {:error, _} ->
        # Already a real copy from a previous mutation
        :ok
    end
  end

  defp mirror_source_tree(root, project_root, dir) do
    source_dir = Path.join(project_root, dir)
    target_dir = Path.join(root, dir)

    if File.dir?(source_dir) do
      source_dir
      |> Path.join("**")
      |> Path.wildcard(match_dot: true)
      |> Enum.each(fn source_path ->
        relative = Path.relative_to(source_path, project_root)
        target_path = Path.join(root, relative)

        if File.dir?(source_path) do
          File.mkdir_p!(target_path)
        else
          File.mkdir_p!(Path.dirname(target_path))
          safe_symlink(source_path, target_path)
        end
      end)

      File.mkdir_p!(target_dir)
    end
  end

  defp link_test_paths(root, project_root, test_paths) do
    for test_path <- test_paths do
      # Test paths may be absolute (resolved against project_root by Config).
      # Relativize so the target inside the sandbox is correct.
      relative_path = Path.relative_to(test_path, project_root)
      source = Path.join(project_root, relative_path)

      link_path(root, project_root, source)
      link_test_root_essentials(root, project_root, source)
    end
  end

  # Symlinks `source` (a file or directory, absolute, inside project_root)
  # into the equivalent location under `root`. Idempotent: skips anything
  # already present at the target (e.g. mirrored by mirror_source_tree, or
  # linked by an earlier call for an overlapping --test-paths entry).
  defp link_path(root, project_root, source) do
    relative_path = Path.relative_to(source, project_root)
    target = Path.join(root, relative_path)

    cond do
      File.dir?(source) ->
        File.mkdir_p!(Path.dirname(target))
        # Only symlink if not already mirrored (e.g. apps/supply_chain/test
        # would already exist from mirror_source_tree on apps/)
        unless File.exists?(target) do
          safe_symlink(source, target)
        end

      File.regular?(source) ->
        # Individual file — ensure parent dir exists
        File.mkdir_p!(Path.dirname(target))

        unless File.exists?(target) do
          safe_symlink(source, target)
        end

      true ->
        :ok
    end
  end

  # `mix help muex` documents narrowing a run with `--test-paths`, e.g. down
  # to a single file. link_path/3 above only symlinks the requested path, so
  # a narrowed sandbox can end up missing test/test_helper.exs (and
  # test/support/, if the project has one) even though the untouched default
  # run of the whole `test` directory happens to pull both in. `mix test`
  # aborts before ExUnit starts without a test helper, and every mutant run
  # then fails identically — silently misclassified as "killed" rather than
  # "the run never happened". Make the Mix test root that owns the requested
  # path runnable regardless of how narrow --test-paths is.
  defp link_test_root_essentials(root, project_root, source) do
    start_dir = if File.dir?(source), do: source, else: Path.dirname(source)

    case find_test_root(start_dir, project_root) do
      nil ->
        :ok

      test_root ->
        case File.ls(test_root) do
          {:ok, entries} ->
            for entry <- entries do
              link_path(root, project_root, Path.join(test_root, entry))
            end

          {:error, _} ->
            :ok
        end
    end
  end

  # Walk up from `dir` toward (and including) `project_root`, returning the
  # first ancestor directory that directly contains a test_helper.exs. This
  # resolves a plain project's test/foo_test.exs (and nested
  # test/a/b/foo_test.exs) to test/, and an umbrella's
  # apps/foo/test/bar_test.exs to apps/foo/test/ — the app's own helper, not
  # the umbrella root. Never escapes above project_root; returns nil (no
  # crash) when no ancestor has a test_helper.exs, since that's a legitimate
  # project shape.
  defp find_test_root(dir, project_root) do
    project_root = Path.expand(project_root)
    dir = Path.expand(dir)

    cond do
      File.regular?(Path.join(dir, "test_helper.exs")) ->
        dir

      dir == project_root ->
        nil

      String.starts_with?(dir, project_root <> "/") ->
        find_test_root(Path.dirname(dir), project_root)

      true ->
        nil
    end
  end

  # Symlink the entire _build tree initially. When apply_mutation is called,
  # ensure_build_copy_for_file/2 replaces the specific app's symlink with a
  # real copy so that sandbox can recompile independently.
  defp setup_build_dir(root, project_root, build_env) do
    source_build = Path.join([project_build_root(project_root), build_env])
    target_build = Path.join([root, "_build", build_env])

    if File.dir?(source_build) do
      File.mkdir_p!(target_build)

      source_lib = Path.join(source_build, "lib")
      target_lib = Path.join(target_build, "lib")

      if File.dir?(source_lib) do
        File.mkdir_p!(target_lib)

        # Symlink ALL app build dirs initially. Deep copies happen lazily
        # in ensure_build_copy_for_file/2 for the mutated app only.
        source_lib
        |> File.ls!()
        |> Enum.each(fn entry ->
          source_entry = Path.join(source_lib, entry)
          target_entry = Path.join(target_lib, entry)
          safe_symlink(source_entry, target_entry)
        end)
      end
    else
      File.mkdir_p!(Path.join([root, "_build", build_env, "lib"]))
    end
  end

  # Delete the stale beam from this sandbox's own build copy, addressed
  # explicitly rather than matched with a wildcard.
  #
  # `Path.wildcard/1` follows symlinks, and every app under the sandbox's
  # `_build` starts life as a symlink into the project's real build directory
  # (see setup_build_dir/3). If ensure_build_copy_for_file/2 could not turn that
  # symlink into a copy — which happens whenever the app name cannot be worked
  # out from the file path — a `**` match walks straight through it and removes
  # the project's compiled modules. Mix will not rebuild them, because the
  # sources have not changed.
  #
  # Doing nothing is the safe failure here: without a copy there is no beam of
  # ours to remove, and the mutation simply does not take effect.
  defp remove_stale_beam(sandbox, file_path, module_name) do
    with app_name when is_binary(app_name) <-
           extract_app_name_from_path(file_path, sandbox.project_root, sandbox.build_env),
         app_build <-
           Path.join([sandbox.root, "_build", sandbox.build_env, "lib", app_name]),
         {:error, _} <- File.read_link(app_build) do
      app_build
      |> Path.join("ebin")
      |> Path.join("#{module_name}.beam")
      |> File.rm()
    end

    :ok
  end

  defp ensure_app_mirrored_for_file(sandbox, file_path) do
    case extract_app_name_from_path(file_path, sandbox.project_root, sandbox.build_env) do
      nil -> :ok
      app_name -> ensure_app_mirrored(sandbox, app_name)
    end
  end

  # Given a file path like "apps/supply_chain/lib/foo.ex", extract the app
  # name ("supply_chain") and ensure its _build/test/lib/<app> directory
  # is a real deep copy (not a symlink) so we can delete its beam files.
  defp ensure_build_copy_for_file(sandbox, file_path) do
    app_name =
      extract_app_name_from_path(file_path, sandbox.project_root, sandbox.build_env)

    if app_name, do: ensure_build_copy(sandbox, app_name)
  end

  defp extract_app_name_from_path(file_path, project_root, build_env) do
    # Canonicalize: strip leading ./ and make relative so Path.split
    # always produces ["apps", app_name, ...] for umbrella paths.
    # Handles ./apps/foo/..., /abs/path/apps/foo/..., and apps/foo/...
    normalized =
      file_path
      |> Path.relative_to(".")
      |> then(fn p ->
        # If still absolute (outside cwd), try to find "apps" segment
        case Path.type(p) do
          :absolute ->
            parts = Path.split(p)

            case Enum.drop_while(parts, &(&1 != "apps")) do
              ["apps" | _] = rest -> Path.join(rest)
              _ -> p
            end

          _ ->
            p
        end
      end)

    # `elixirc_paths` accepts any directory, so sources legitimately live
    # outside `lib/`. Anything that is not an umbrella path falls back to
    # reading the app name out of the build directory.
    case Path.split(normalized) do
      ["apps", app_name | _] -> app_name
      _ -> app_name_of_project(project_root, build_env)
    end
  end

  # Outside an umbrella every source file belongs to the project's own app, and
  # the project states that app's name — reading it is exact. Only fall back to
  # inferring it from the build directory, which cannot tell the app under test
  # apart from its dependencies.
  defp app_name_of_project(project_root, build_env) do
    app_from_loaded_project(project_root) ||
      app_from_mix_exs(project_root) ||
      detect_app_from_build(project_root, build_env)
  end

  # muex runs as a Mix task inside the project it mutates, so Mix has usually
  # already evaluated its `mix.exs` and holds the canonical value — including
  # for the `mix.exs` files that compute `:app` rather than writing it out.
  # Only trust it when the loaded project really is this one (muex can be
  # pointed at an external project), and never for an umbrella root, whose
  # `:app` is not the app any source file belongs to.
  defp app_from_loaded_project(project_root) do
    if Mix.Project.get() && not Mix.Project.umbrella?() &&
         same_directory?(Path.dirname(Mix.Project.project_file()), project_root) do
      to_app_name(Mix.Project.config()[:app])
    end
  rescue
    _ -> nil
  end

  # Otherwise read the name out of `mix.exs` without evaluating it: the `:app`
  # entry of `def project`, resolving `app: @app` against the attribute's
  # definition in the same file.
  defp app_from_mix_exs(project_root) do
    with {:ok, source} <- File.read(Path.join(project_root, "mix.exs")),
         {:ok, ast} <- Code.string_to_quoted(source),
         value when not is_nil(value) <- project_option(ast, :app) do
      value |> resolve_attribute(ast) |> to_app_name()
    else
      _ -> nil
    end
  end

  # Only the options `def project` returns at the top level count. A nested
  # `app:` is a different option that happens to share the name — `escript:`
  # takes one — so searching the body for the first `app:` anywhere can answer
  # with the wrong app whenever the nested one comes first.
  defp project_option(ast, key) do
    with {:def, _meta, [{:project, _, _}, [do: body]]} <-
           find_node(ast, &match?({:def, _meta, [{:project, _, _}, [do: _body]]}, &1)),
         options when is_list(options) <- project_options(body),
         {^key, value} <- List.keyfind(options, key, 0) do
      value
    else
      _ -> nil
    end
  end

  # `def project` either ends in the options list itself or does so after other
  # expressions. A body that computes the list instead is not read here; it
  # falls through to inferring the name from the build directory.
  defp project_options({:__block__, _meta, expressions}),
    do: expressions |> List.last() |> project_options()

  defp project_options(options) when is_list(options), do: options
  defp project_options(_other), do: nil

  defp resolve_attribute({:@, _meta, [{name, _, ctx}]}, ast)
       when is_atom(name) and is_atom(ctx) do
    case find_node(ast, &match?({:@, _meta, [{^name, _, [_value]}]}, &1)) do
      {:@, _meta, [{^name, _, [value]}]} -> value
      _ -> nil
    end
  end

  defp resolve_attribute(value, _ast), do: value

  defp find_node(ast, fun) do
    {_ast, found} =
      Macro.prewalk(ast, nil, fn node, acc ->
        if is_nil(acc) and fun.(node), do: {node, node}, else: {node, acc}
      end)

    found
  end

  defp same_directory?(a, b), do: Path.expand(a) == Path.expand(b)

  defp to_app_name(app) when is_atom(app) and not is_nil(app), do: Atom.to_string(app)
  defp to_app_name(_app), do: nil

  # Last resort, for a project whose name could not be read: infer it from the
  # build directory. Every compiled dependency leaves the same marker, so this
  # can only answer when exactly one app is built — which is to say, almost
  # never once the project has a single dependency.
  defp detect_app_from_build(project_root, build_env) do
    # Use the project root (not CWD) so this works for external projects, and
    # the sandbox's own build env rather than assuming "test".
    lib_dir = Path.join([project_build_root(project_root), build_env, "lib"])

    case Path.wildcard(Path.join([lib_dir, "*", ".mix", "compile.elixir"]), match_dot: true) do
      [path] ->
        path |> Path.relative_to(lib_dir) |> Path.split() |> List.first()

      _ ->
        # Either nothing is built yet, or this is an umbrella and the file path
        # did not name an app. Guessing would target the wrong one.
        nil
    end
  end

  # Mix writes to $MIX_BUILD_ROOT when it is set, so a run started from a task
  # that sets it does not use `<project>/_build` at all. Copying from the wrong
  # place leaves the sandbox pointing at the real build directory.
  defp project_build_root(project_root) do
    case System.get_env("MIX_BUILD_ROOT") do
      nil -> Path.join(project_root, "_build")
      "" -> Path.join(project_root, "_build")
      root -> Path.expand(root, project_root)
    end
  end

  defp ensure_build_copy(sandbox, app_name) do
    target_app_build = Path.join([sandbox.root, "_build", sandbox.build_env, "lib", app_name])

    source_app_build =
      Path.join([
        project_build_root(sandbox.project_root),
        sandbox.build_env,
        "lib",
        app_name
      ])

    # If it's a symlink, replace with a deep copy
    case File.read_link(target_app_build) do
      {:ok, _} ->
        # It's a symlink — replace with a real copy
        File.rm!(target_app_build)
        deep_copy(source_app_build, target_app_build)

      {:error, _} ->
        # Already a real directory (from a previous mutation on same app)
        :ok
    end
  end

  # Use system cp with clone/reflink for copy-on-write when available (macOS APFS,
  # Linux btrfs/xfs). Falls back to regular copy. This is orders of magnitude
  # faster than recursive File.cp! for large directory trees.
  defp deep_copy(source, target) do
    # macOS: -c enables clonefile (COW), -R recursive
    # Linux: --reflink=auto for COW on btrfs/xfs
    case :os.type() do
      {:unix, :darwin} ->
        {_, 0} = System.cmd("cp", ["-Rc", source, target])

      {:unix, _} ->
        case System.cmd("cp", ["-R", "--reflink=auto", source, target], stderr_to_stdout: true) do
          {_, 0} -> :ok
          _ -> File.cp_r!(source, target)
        end

      _ ->
        File.cp_r!(source, target)
    end
  end

  defp safe_symlink(source, target) do
    File.rm(target)
    File.ln_s!(source, target)
  end
end
