defmodule Mix.Tasks.Arch.Check do
  use Mix.Task

  @shortdoc "Check architecture rules defined in arch.exs"

  @moduledoc """
  Evaluates the layer rules defined in your architecture config file
  and reports any violations.

      mix arch.check
      mix arch.check --config path/to/arch.exs
      mix arch.check --no-cache

  ## Options

    * `--config` — path to the config file (default: `"arch.exs"`)
    * `--no-cache` — bypass the dependency graph cache

  ## Environment variables

    * `ExArchUnit_PROFILE=1` — print build/evaluation stats
  """

  alias ExArchUnit.Config
  alias ExArchUnit.Graph.Cache
  alias ExArchUnit.Reporter
  alias ExArchUnit.Rule.Evaluator

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [config: :string, no_cache: :boolean],
        aliases: [c: :config]
      )

    config_path = Keyword.get(opts, :config, Config.default_config_path())

    if Keyword.get(opts, :no_cache, false) do
      System.put_env("ExArchUnit_NO_CACHE", "1")
    end

    config = Config.load!(config_path)
    {graph, stats} = Cache.get_or_build(config)

    case Evaluator.evaluate_layer_rules(graph, config) do
      :ok ->
        Mix.shell().info("All architecture rules passed.")

      {:error, layer_rule_violations} ->
        formatted = Reporter.format_layer_rules(layer_rule_violations)
        Mix.shell().error(formatted)
        Mix.raise("Architecture rules violated. See above for details.")
    end

    if System.get_env("ExArchUnit_PROFILE") == "1" do
      Mix.shell().info("Stats: #{inspect(stats)}")
    end
  end
end
