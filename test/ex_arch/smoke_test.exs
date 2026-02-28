defmodule ExArch.SmokeTest do
  use ExUnit.Case, async: false
  use ExArch, config: "fixtures/arch_smoke.exs", enforce_config_rules: false

  test "minimal end-to-end violation is readable" do
    error =
      assert_raise ExUnit.AssertionError, fn ->
        forbid("ExArchFixture.Smoke.A", depends_on: "ExArchFixture.Smoke.B")
      end

    assert error.message =~ "ExArchFixture.Smoke.A -> ExArchFixture.Smoke.B"
  end

  test "minimal allow rule can pass" do
    assert :ok == allow("ExArchFixture.Smoke.A", depends_on: "ExArchFixture.Smoke.B")
  end
end
