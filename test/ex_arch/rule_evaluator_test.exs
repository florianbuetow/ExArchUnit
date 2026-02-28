defmodule ExArch.RuleEvaluatorTest do
  use ExUnit.Case, async: false

  alias ExArch.Config
  alias ExArch.Graph.Cache
  alias ExArch.Rule.Evaluator

  setup do
    Cache.clear()
    :ok
  end

  test "forbid identifies violating dependencies" do
    config =
      Config.load!("fixtures/arch_test.exs")
      |> Map.put(:cache, false)
      |> Map.put(:include, ["ExArchFixture.Bad.*"])

    {graph, _stats} = Cache.get_or_build(config)

    assert {:error, violations} =
             Evaluator.forbid(
               graph,
               config,
               "ExArchFixture.Bad.Domain.*",
               "ExArchFixture.Bad.Web.*"
             )

    assert {"ExArchFixture.Bad.Domain.Service", "ExArchFixture.Bad.Web.Endpoint"} in Enum.map(
             violations,
             fn {source, target} ->
               {ExArch.Graph.module_name(source), ExArch.Graph.module_name(target)}
             end
           )
  end

  test "allow rejects dependencies outside allow list" do
    config =
      Config.load!("fixtures/arch_test.exs")
      |> Map.put(:cache, false)
      |> Map.put(:include, ["ExArchFixture.Bad.*"])

    {graph, _stats} = Cache.get_or_build(config)

    assert {:error, violations} =
             Evaluator.allow(
               graph,
               config,
               "ExArchFixture.Bad.Domain.*",
               "ExArchFixture.Bad.Domain.*"
             )

    assert length(violations) >= 1
  end

  test "assert_no_cycles detects SCC cycles" do
    config =
      Config.load!("fixtures/arch_test.exs")
      |> Map.put(:cache, false)
      |> Map.put(:include, ["ExArchFixture.Cycle.*"])

    {graph, _stats} = Cache.get_or_build(config)

    assert {:error, cycles} =
             Evaluator.assert_no_cycles(graph, config, prefix: "ExArchFixture.Cycle.*")

    assert Enum.any?(cycles, fn cycle ->
             names = Enum.map(cycle, &ExArch.Graph.module_name/1)
             "ExArchFixture.Cycle.A" in names and "ExArchFixture.Cycle.B" in names
           end)
  end

  test "selector resolution supports layer atoms and list unions" do
    config =
      Config.load!("fixtures/arch_test.exs")
      |> Map.put(:cache, false)
      |> Map.put(:include, ["ExArchFixture.Bad.*", "ExArchFixture.Cycle.*"])

    {graph, _stats} = Cache.get_or_build(config)

    by_layer = Evaluator.resolve_selector(graph, config, :bad_domain)
    by_pattern = Evaluator.resolve_selector(graph, config, "ExArchFixture.Bad.Domain.*")
    union = Evaluator.resolve_selector(graph, config, [:bad_domain, "ExArchFixture.Cycle.*"])

    assert MapSet.equal?(by_layer, by_pattern)
    assert MapSet.size(union) > MapSet.size(by_layer)
  end
end
