defmodule ExArchUnit.ReporterTest do
  use ExUnit.Case, async: true

  alias ExArchUnit.Reporter
  alias ExArchUnit.Rule

  # --- format_forbid/3 ---

  test "format_forbid with violations lists them" do
    violations = [{:"Elixir.A.Service", :"Elixir.B.Endpoint"}]
    msg = Reporter.format_forbid("A.*", "B.*", violations)
    assert msg =~ "A.Service -> B.Endpoint"
    assert msg =~ "Violations (1)"
  end

  test "format_forbid with multiple violations" do
    violations = [
      {:"Elixir.Z.Mod", :"Elixir.A.Mod"},
      {:"Elixir.A.Mod", :"Elixir.B.Mod"}
    ]

    msg = Reporter.format_forbid("*", "*", violations)
    assert msg =~ "Violations (2)"
  end

  test "format_forbid with empty violations" do
    msg = Reporter.format_forbid("A.*", "B.*", [])
    assert msg =~ "Violations (0)"
  end

  # --- format_allow/3 ---

  test "format_allow with violations" do
    violations = [{:"Elixir.A.Mod", :"Elixir.C.Mod"}]
    msg = Reporter.format_allow("A.*", "B.*", violations)
    assert msg =~ "A.Mod -> C.Mod"
    assert msg =~ "Disallowed dependencies (1)"
  end

  test "format_allow with empty violations" do
    msg = Reporter.format_allow("A.*", "B.*", [])
    assert msg =~ "Disallowed dependencies (0)"
  end

  # --- format_cycles/2 ---

  test "format_cycles with a multi-module cycle" do
    cycles = [[:"Elixir.A", :"Elixir.B"]]
    msg = Reporter.format_cycles("*", cycles)
    assert msg =~ "Cycles (1)"
    assert msg =~ "A -> B -> A"
  end

  test "format_cycles with empty cycles" do
    msg = Reporter.format_cycles("*", [])
    assert msg =~ "Cycles (0)"
  end

  # --- format_layer_rules/1 ---

  test "format_layer_rules with violations" do
    rule = %Rule{type: :forbid, source: :domain, depends_on: [:web]}

    rule_violations = [
      %{rule: rule, violations: [{:"Elixir.D.Svc", :"Elixir.W.Ctrl"}]}
    ]

    msg = Reporter.format_layer_rules(rule_violations)
    assert msg =~ "D.Svc -> W.Ctrl"
    assert msg =~ "Architecture config rules violated"
  end

  test "format_layer_rules with empty list" do
    msg = Reporter.format_layer_rules([])
    assert is_binary(msg)
    assert msg =~ "Architecture config rules violated"
  end
end
