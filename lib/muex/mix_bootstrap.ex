defmodule Muex.MixBootstrap do
  @moduledoc """
  Starts Mix and loads the project's `mix.exs` inside the escript.

  An escript carries its own Elixir runtime but not Mix, and it never evaluates
  the `mix.exs` of the project it is run in. `Muex.CLI` therefore starts Mix
  itself and evaluates the project's `mix.exs` before anything asks for
  `Mix.Project`. This module is that bootstrap, kept apart from the CLI so it can
  be tested without halting the VM.

  ## Where Mix comes from

  The escript embeds Elixir but Mix is loaded from the Elixir installation the
  `elixir` executable on `PATH` belongs to (`<elixir>/lib/mix/ebin`). The same
  installation supplies `eex` and `ex_unit`, which `mix test` needs. Mix is
  loaded at runtime rather than embedded in the escript because it evaluates the
  `mix.exs` of the project it runs in, and so belongs to that project's Elixir
  version, not to the one muex was built with.

  A project that cannot supply Mix is refused with an explanation instead of a
  `Mix.start/0 is undefined` stack trace.

  ## Loading the project

  `load_project/1` evaluates `mix.exs` the way `mix` itself does, so `mix muex`
  and `muex` see the same project: the same app name, the same umbrella. It does
  not run `loadpaths` or `compile`: `Muex.Sandbox` is the only part of muex that
  reads the loaded project, and only for its `:app`, while every test run
  compiles in its own sandbox. Running `loadpaths` here would rewrite the code
  path for the loaded project, dropping the directory muex itself is running
  from when that is a `_build` of another project.
  """

  @typedoc """
  Why the project could not be loaded.

    * `:no_mix` - Mix could not be found next to the `elixir` on `PATH`.
    * `:no_project` - no `mix.exs` was found at or above the working directory.
    * `:load_failed` - `mix.exs` raised while it was evaluated.
  """
  @type error ::
          {:no_mix, String.t()}
          | {:no_project, Path.t()}
          | {:load_failed, Path.t(), Exception.t()}

  @doc """
  Starts Mix, evaluating `project_file` as the current project.

  When `project_file` is `nil` or does not exist, Mix is started but no project
  is loaded; `load_project/1` is the entry point that reports `{:no_project, _}`.

  Returns `:ok`, `{:error, {:no_mix, reason}}` when Mix is not available, or
  `{:error, {:load_failed, file, exception}}` when `mix.exs` raises.
  """
  @spec start(String.t() | nil) :: :ok | {:error, {:no_mix, String.t()} | error()}
  def start(project_file \\ nil) do
    with :ok <- start_mix() do
      if project_file && File.regular?(project_file) do
        # `mix` evaluates `mix.exs` from the project directory; do the same so a
        # `mix.exs` that reads files relative to the working directory behaves
        # as it does under `mix muex`.
        load_project_file(project_file)
      else
        :ok
      end
    end
  end

  # `use Mix.Project` evaluates `project/0` while the module is compiled, so a
  # `mix.exs` that raises leaves a half-pushed project behind. Drop it, so the
  # next attempt starts clean, and report what went wrong.
  defp load_project_file(project_file) do
    in_project_dir(project_file, fn -> Code.require_file(project_file) end)
    :ok
  rescue
    e ->
      Mix.ProjectStack.clear_stack()
      {:error, {:load_failed, project_file, e}}
  end

  @doc """
  Starts Mix and loads the project at or above `dir`.

  `dir` defaults to the working directory. On success `Mix.Project.get/0`
  returns the project's module and `Mix.Project.project_file/0` names its
  `mix.exs`, exactly as under `mix muex`.
  """
  @spec load_project(Path.t()) :: :ok | {:error, error()}
  def load_project(dir \\ File.cwd!()) do
    case find_project_file(dir) do
      nil -> {:error, {:no_project, Path.expand(dir)}}
      project_file -> start(project_file)
    end
  end

  @doc """
  Formats an error from `load_project/1` as a message for the user.
  """
  @spec format_error(error()) :: String.t()
  def format_error({:no_mix, reason}) do
    """
    Mix is not available: #{reason}

    The escript does not embed Mix; it loads the one shipped with the Elixir
    installation that provides the `elixir` executable on your PATH. Install
    Elixir, or put its `bin` directory on PATH, and run muex again.
    """
    |> String.trim_trailing()
  end

  def format_error({:no_project, dir}) do
    """
    No mix.exs found in #{dir} or any directory above it.
    Please run muex from the root of an Elixir project.
    """
    |> String.trim_trailing()
  end

  def format_error({:load_failed, project_file, exception}) do
    """
    Could not load #{project_file}: #{Exception.message(exception)}
    """
    |> String.trim_trailing()
  end

  @doc """
  The `mix.exs` at or above `dir`, or `nil` when there is none.

  Mirrors how `mix` finds the project it is run in: the nearest `mix.exs`
  walking up from the working directory.
  """
  @spec find_project_file(Path.t()) :: Path.t() | nil
  def find_project_file(dir) do
    dir = Path.expand(dir)
    candidate = Path.join(dir, "mix.exs")
    parent = Path.dirname(dir)

    cond do
      File.regular?(candidate) -> candidate
      parent == dir -> nil
      true -> find_project_file(parent)
    end
  end

  # The Elixir installation is the one that owns the `elixir` executable on
  # PATH: `<elixir>/bin/elixir` sits beside `<elixir>/lib/mix/ebin`. The escript
  # itself runs from an embedded Elixir, so `:code.lib_dir/1` cannot answer.
  defp start_mix do
    case elixir_lib_dir() do
      nil ->
        {:error, {:no_mix, "no `elixir` executable was found on PATH"}}

      lib_dir ->
        mix_ebin = Path.join(lib_dir, "mix/ebin")

        if File.dir?(mix_ebin) do
          # eex and ex_unit are needed by `mix test`, which muex runs for every
          # mutant; adding them here means the child VM inherits them.
          Enum.each(["eex", "ex_unit", "mix"], &add_lib(&1, lib_dir))
          start_apps()
        else
          {:error, {:no_mix, "no Mix was found in #{lib_dir}"}}
        end
    end
  end

  defp elixir_lib_dir do
    case System.find_executable("elixir") do
      nil ->
        nil

      elixir ->
        lib_dir = elixir |> Path.dirname() |> Path.join("..") |> Path.join("lib") |> Path.expand()
        if File.dir?(lib_dir), do: lib_dir
    end
  end

  defp add_lib(app, lib_dir) do
    ebin = Path.join([lib_dir, app, "ebin"])

    if File.dir?(ebin) and ebin not in :code.get_path() do
      :code.add_patha(String.to_charlist(ebin))
    end
  end

  defp start_apps do
    Application.ensure_all_started(:mix)
    :ok
  end

  defp in_project_dir(project_file, fun) do
    dir = Path.dirname(project_file)
    previous = File.cwd!()

    if Path.expand(dir) == Path.expand(previous) do
      fun.()
    else
      try do
        File.cd!(dir, fun)
      after
        File.cd!(previous)
      end
    end
  end
end
