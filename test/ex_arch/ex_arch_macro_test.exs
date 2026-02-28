defmodule ExArch.MacroEdgeCaseTest do
  use ExUnit.Case, async: false
  use ExArch, config: "fixtures/arch_test.exs", enforce_config_rules: false

  # --- assert_no_cycles with :in option ---

  test "assert_no_cycles with :in option detects cycles" do
    assert_raise ExUnit.AssertionError, fn ->
      assert_no_cycles(in: "ExArchFixture.Cycle.*")
    end
  end

  test "assert_no_cycles passes when no cycles exist" do
    assert_no_cycles(prefix: "ExArchFixture.Bad.Domain.*")
  end

  # --- missing :depends_on ---

  test "forbid raises ArgumentError when depends_on is missing" do
    assert_raise ArgumentError, ~r/expects :depends_on/, fn ->
      forbid("A.*", [])
    end
  end

  test "allow raises ArgumentError when depends_on is missing" do
    assert_raise ArgumentError, ~r/expects :depends_on/, fn ->
      allow("A.*", [])
    end
  end

  # --- missing :prefix and :in ---

  test "assert_no_cycles raises ArgumentError when neither :prefix nor :in given" do
    assert_raise ArgumentError, fn ->
      assert_no_cycles([])
    end
  end

  # --- allow macro passes ---

  test "allow passes for valid Ok.Web -> Ok.Domain dependency" do
    allow("ExArchFixture.Ok.Web.*", depends_on: "ExArchFixture.Ok.Domain.*")
  end

  # --- allow macro fails ---

  test "allow raises on disallowed dependency" do
    assert_raise ExUnit.AssertionError, fn ->
      allow("ExArchFixture.Bad.Domain.*", depends_on: "ExArchFixture.Bad.Domain.*")
    end
  end

  # --- forbid passes when no violations ---

  test "forbid passes when there are no violations" do
    forbid("ExArchFixture.Ok.Domain.*", depends_on: "ExArchFixture.Ok.Web.*")
  end
end
