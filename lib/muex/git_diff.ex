defmodule Muex.GitDiff do
  @moduledoc """
  Maps a git diff to the set of source lines a change touched, so mutation
  testing can be scoped to exactly what a branch/PR modified.

  `changed_lines/1` is a pure parser over `git diff --unified=0` output;
  `changed_since/2` shells out to `git` and feeds it that parser.
  """

  # `@@ -<old> +<newStart>[,<newCount>] @@` — we only care about the new-file
  # side, since that is what exists to be mutated.
  @hunk ~r/^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/

  @doc """
  Parses `git diff --unified=0` output into `%{path => MapSet of line numbers}`.

  Only added/modified lines on the new-file side are recorded. Deleted files and
  pure-deletion hunks contribute nothing.
  """
  @spec changed_lines(String.t()) :: %{String.t() => MapSet.t(pos_integer())}
  def changed_lines(diff) when is_binary(diff) do
    diff
    |> String.split("\n")
    |> Enum.reduce({nil, %{}}, &parse_line/2)
    |> elem(1)
  end

  @doc """
  Returns the lines changed on the current branch relative to `ref`.

  Uses `git diff --unified=0 <ref>...HEAD`, i.e. changes since the branch
  diverged from `ref` (PR semantics). Returns `{:ok, map}` or `{:error, reason}`.
  """
  @spec changed_since(String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def changed_since(ref, opts \\ []) when is_binary(ref) do
    cd = Keyword.get(opts, :cd, File.cwd!())
    args = ["diff", "--unified=0", "--no-color", "#{ref}...HEAD"]

    case System.cmd("git", args, cd: cd, stderr_to_stdout: true) do
      {output, 0} -> {:ok, changed_lines(output)}
      {output, _code} -> {:error, String.trim(output)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Keeps only the mutations whose location falls on a changed line.

  `changed` is a map as returned by `changed_lines/1`/`changed_since/2`, or
  `nil` to disable filtering (returns every mutation unchanged).
  """
  @spec filter_mutations([map()], map() | nil) :: [map()]
  def filter_mutations(mutations, nil), do: mutations

  def filter_mutations(mutations, changed) when is_map(changed) do
    Enum.filter(mutations, fn mutation ->
      case Map.get(changed, mutation.location.file) do
        nil -> false
        lines -> MapSet.member?(lines, mutation.location.line)
      end
    end)
  end

  # New-file path line: `+++ b/path` (or `+++ /dev/null` for deletions).
  defp parse_line("+++ /dev/null", {_path, acc}), do: {:skip, acc}

  defp parse_line("+++ " <> path, {_path, acc}) do
    {strip_prefix(path), acc}
  end

  defp parse_line(line, {path, acc}) do
    case Regex.run(@hunk, line) do
      [_, start] -> {path, add_lines(acc, path, to_int(start), 1)}
      [_, start, count] -> {path, add_lines(acc, path, to_int(start), to_int(count))}
      nil -> {path, acc}
    end
  end

  # No new-file path yet (or a deleted file), or a pure-deletion hunk: nothing
  # to record.
  defp add_lines(acc, path, _start, _count) when path in [nil, :skip], do: acc
  defp add_lines(acc, _path, _start, 0), do: acc

  defp add_lines(acc, path, start, count) do
    lines = MapSet.new(start..(start + count - 1))
    Map.update(acc, path, lines, &MapSet.union(&1, lines))
  end

  defp to_int(string), do: String.to_integer(string)

  # Diff paths are prefixed with `b/`; a `b/` literally named file would be rare
  # but we only strip the conventional prefix.
  defp strip_prefix("b/" <> rest), do: rest
  defp strip_prefix(other), do: other
end
