defmodule ExArchUnit.IntegrationTest do
  use ExUnit.Case, async: false
  use ExArchUnit, config: "fixtures/arch_test.exs", enforce_config_rules: false

  test "forbid macro surfaces ExUnit assertion failures" do
    assert_raise ExUnit.AssertionError, fn ->
      forbid("ExArchFixture.Bad.Domain.*", depends_on: "ExArchFixture.Bad.Web.*")
    end
  end

  test "allow macro can pass for valid dependencies" do
    assert :ok == allow("ExArchFixture.Ok.Web.*", depends_on: "ExArchFixture.Ok.Domain.*")
  end

  test "assert_no_cycles macro surfaces cycles as assertion failures" do
    assert_raise ExUnit.AssertionError, fn ->
      assert_no_cycles(prefix: "ExArchFixture.Cycle.*")
    end
  end
end
