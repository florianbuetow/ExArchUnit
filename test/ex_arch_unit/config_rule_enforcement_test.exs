defmodule ExArchUnit.ConfigRuleEnforcementTest do
  use ExUnit.Case, async: false

  alias ExArchUnit.Config
  alias ExArchUnit.Graph.Cache
  alias ExArchUnit.Rule.Evaluator

  setup do
    Cache.clear()
    :ok
  end

  test "configured layer rules can be evaluated and fail on violations" do
    config =
      Config.load!("fixtures/arch_test.exs")
      |> Map.put(:cache, false)
      |> Map.put(:include, ["ExArchFixture.Bad.*"])

    {graph, _stats} = Cache.get_or_build(config)

    assert {:error, layer_rule_violations} = Evaluator.evaluate_layer_rules(graph, config)
    assert length(layer_rule_violations) > 0
  end

  test "use ExArchUnit enforces valid config rules in setup_all" do
    assert Code.ensure_loaded?(ExArchUnit.ConfigRuleEnforcementPassTest)
  end
end

defmodule ExArchUnit.ConfigRuleEnforcementPassTest do
  use ExUnit.Case, async: false
  use ExArchUnit, config: "fixtures/arch_ok.exs"

  test "setup_all passed config rule enforcement" do
    assert true
  end
end
