defmodule ExArchUnit.BehaviourEdgesTest do
  use ExUnit.Case, async: false

  alias ExArchUnit.Config
  alias ExArchUnit.Graph.Builder
  alias ExArchUnit.Rule.Evaluator

  test "behaviour edges are included only when include_behaviours is enabled" do
    base_config =
      Config.load!("fixtures/arch_test.exs")
      |> Map.put(:cache, false)
      |> Map.put(:include, ["ExArchFixture.Behaviour.*"])
      |> Map.put(:layers, %{
        impl: "ExArchFixture.Behaviour.Impl",
        contract: "ExArchFixture.Behaviour.Contract"
      })
      |> Map.put(:layer_rules, [])

    {graph_without_behaviours, _} = Builder.build(base_config)

    assert :ok =
             Evaluator.forbid(
               graph_without_behaviours,
               base_config,
               "ExArchFixture.Behaviour.Impl",
               "ExArchFixture.Behaviour.Contract"
             )

    config_with_behaviours = Map.put(base_config, :include_behaviours, true)
    {graph_with_behaviours, _} = Builder.build(config_with_behaviours)

    assert {:error, violations} =
             Evaluator.forbid(
               graph_with_behaviours,
               config_with_behaviours,
               "ExArchFixture.Behaviour.Impl",
               "ExArchFixture.Behaviour.Contract"
             )

    assert Enum.any?(violations, fn {source, target} ->
             ExArchUnit.Graph.module_name(source) == "ExArchFixture.Behaviour.Impl" and
               ExArchUnit.Graph.module_name(target) == "ExArchFixture.Behaviour.Contract"
           end)
  end
end
