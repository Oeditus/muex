defmodule Muex.GitDiffTest do
  use ExUnit.Case, async: true

  alias Muex.GitDiff

  describe "changed_lines/1" do
    test "captures added/modified lines from a single hunk (new-file side)" do
      diff = """
      diff --git a/lib/foo.ex b/lib/foo.ex
      index 1111111..2222222 100644
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -10,1 +10,3 @@ def foo do
      +  a
      +  b
      +  c
      """

      assert GitDiff.changed_lines(diff) == %{"lib/foo.ex" => MapSet.new([10, 11, 12])}
    end

    test "merges multiple hunks within one file" do
      diff = """
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -1,0 +2,1 @@
      +x
      @@ -20,0 +40,2 @@
      +y
      +z
      """

      assert GitDiff.changed_lines(diff) == %{"lib/foo.ex" => MapSet.new([2, 40, 41])}
    end

    test "handles multiple files" do
      diff = """
      --- a/lib/a.ex
      +++ b/lib/a.ex
      @@ -1,0 +1,1 @@
      +a
      --- a/lib/b.ex
      +++ b/lib/b.ex
      @@ -5,0 +5,1 @@
      +b
      """

      assert GitDiff.changed_lines(diff) ==
               %{"lib/a.ex" => MapSet.new([1]), "lib/b.ex" => MapSet.new([5])}
    end

    test "treats an omitted hunk count as 1" do
      diff = """
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -3 +7 @@
      +line
      """

      assert GitDiff.changed_lines(diff) == %{"lib/foo.ex" => MapSet.new([7])}
    end

    test "captures every line of a newly added file" do
      diff = """
      diff --git a/lib/new.ex b/lib/new.ex
      new file mode 100644
      --- /dev/null
      +++ b/lib/new.ex
      @@ -0,0 +1,3 @@
      +one
      +two
      +three
      """

      assert GitDiff.changed_lines(diff) == %{"lib/new.ex" => MapSet.new([1, 2, 3])}
    end

    test "ignores deleted files (no new-file side)" do
      diff = """
      diff --git a/lib/gone.ex b/lib/gone.ex
      deleted file mode 100644
      --- a/lib/gone.ex
      +++ /dev/null
      @@ -1,2 +0,0 @@
      -old
      -code
      """

      assert GitDiff.changed_lines(diff) == %{}
    end

    test "ignores a pure-deletion hunk (zero added lines)" do
      diff = """
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -10,2 +9,0 @@
      -removed
      -removed2
      """

      assert GitDiff.changed_lines(diff) == %{}
    end

    test "returns an empty map for empty input" do
      assert GitDiff.changed_lines("") == %{}
    end
  end

  describe "changed_since/2 (real git)" do
    @describetag :tmp_dir

    defp git!(args, dir), do: {_, 0} = System.cmd("git", args, cd: dir, stderr_to_stdout: true)

    setup %{tmp_dir: dir} do
      git!(["init", "-q"], dir)
      git!(["config", "user.email", "t@example.com"], dir)
      git!(["config", "user.name", "Test"], dir)
      %{dir: dir}
    end

    test "returns the lines modified on the branch since a ref", %{dir: dir} do
      file = Path.join(dir, "calc.ex")
      File.write!(file, "one\ntwo\nthree\n")
      git!(["add", "."], dir)
      git!(["commit", "-q", "-m", "init"], dir)

      File.write!(file, "one\nCHANGED\nthree\n")
      git!(["commit", "-q", "-am", "change line 2"], dir)

      assert GitDiff.changed_since("HEAD~1", cd: dir) == {:ok, %{"calc.ex" => MapSet.new([2])}}
    end

    test "records every line of a newly added file", %{dir: dir} do
      File.write!(Path.join(dir, "seed.ex"), "x\n")
      git!(["add", "."], dir)
      git!(["commit", "-q", "-m", "seed"], dir)

      File.write!(Path.join(dir, "added.ex"), "a\nb\n")
      git!(["add", "."], dir)
      git!(["commit", "-q", "-m", "add file"], dir)

      assert {:ok, changed} = GitDiff.changed_since("HEAD~1", cd: dir)
      assert changed == %{"added.ex" => MapSet.new([1, 2])}
    end

    test "returns an error for an unknown ref", %{dir: dir} do
      File.write!(Path.join(dir, "x.ex"), "x\n")
      git!(["add", "."], dir)
      git!(["commit", "-q", "-m", "init"], dir)

      assert {:error, reason} = GitDiff.changed_since("no-such-ref-xyz", cd: dir)
      assert is_binary(reason)
    end
  end

  describe "filter_mutations/2" do
    setup do
      changed = %{"lib/a.ex" => MapSet.new([10, 11]), "lib/b.ex" => MapSet.new([5])}

      mutations = [
        %{location: %{file: "lib/a.ex", line: 10}},
        %{location: %{file: "lib/a.ex", line: 99}},
        %{location: %{file: "lib/b.ex", line: 5}},
        %{location: %{file: "lib/c.ex", line: 5}}
      ]

      %{changed: changed, mutations: mutations}
    end

    test "keeps only mutations on changed lines of changed files", ctx do
      kept = GitDiff.filter_mutations(ctx.mutations, ctx.changed)

      assert kept == [
               %{location: %{file: "lib/a.ex", line: 10}},
               %{location: %{file: "lib/b.ex", line: 5}}
             ]
    end

    test "returns all mutations unchanged when given nil (no --since)", ctx do
      assert GitDiff.filter_mutations(ctx.mutations, nil) == ctx.mutations
    end
  end
end
