defmodule Mix.Tasks.MuexTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Muex, as: MuexTask

  test "mix muex raises when zero mutations are tested and fail_at is not met" do
    # When files list matches no mutable code or empty directory, run returns results: []
    # If fail-at 80 is set, it should raise a Mix.Error instead of passing silently.
    assert_raise Mix.Error, ~r/Mutation score 0.0% is below threshold 80%/, fn ->
      MuexTask.run(["--files", "non_existent_dir_12345", "--fail-at", "80"])
    end
  end

  test "mix muex passes when zero mutations are tested and fail-at is 0" do
    # If fail-at is 0, score 0.0% is not below threshold 0%
    assert MuexTask.run(["--files", "non_existent_dir_12345", "--fail-at", "0"]) == nil
  end
end
