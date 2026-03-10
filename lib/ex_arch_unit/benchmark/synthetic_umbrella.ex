defmodule ExArchUnit.Benchmark.SyntheticUmbrella do
  @moduledoc false

  alias ExArchUnit.Config
  alias ExArchUnit.Graph
  alias ExArchUnit.Graph.Cache
  alias ExArchUnit.Rule.Evaluator

  @spec run(keyword()) :: map()
  def run(opts \\ []) do
    apps = Keyword.get(opts, :apps, 4)
    modules_per_app = Keyword.get(opts, :modules_per_app, 60)
    mix_env = Keyword.get(opts, :mix_env, Atom.to_string(Mix.env()))
    cleanup? = Keyword.get(opts, :cleanup, true)

    tmp_dir =
      Keyword.get(
        opts,
        :tmp_dir,
        Path.join(System.tmp_dir!(), "ex_arch_bench_#{System.unique_integer([:positive])}")
      )

    File.rm_rf!(tmp_dir)
    create_synthetic_umbrella!(tmp_dir, apps, modules_per_app)

    {compile_output, compile_exit} =
      System.cmd("mix", ["compile"],
        cd: tmp_dir,
        env: [{"MIX_ENV", mix_env}],
        stderr_to_stdout: true
      )

    if compile_exit != 0 do
      raise RuntimeError, "Synthetic umbrella compile failed:\n#{compile_output}"
    end

    results =
      Mix.Project.in_project(:ex_arch_benchmark_umbrella, tmp_dir, fn _ ->
        config =
          Config.load!(Path.join(tmp_dir, "arch.exs"))
          |> Map.put(:cache, true)
          |> Map.put(:include, ["BenchUmbrella.*"])

        Cache.clear()

        {first_graph, first_stats, first_ms} = timed(fn -> Cache.get_or_build(config) end)
        {_second_graph, second_stats, second_ms} = timed(fn -> Cache.get_or_build(config) end)

        {_layer_result, layer_rules_ms} =
          timed(fn -> Evaluator.evaluate_layer_rules(first_graph, config) end)

        %{
          apps: apps,
          modules_per_app: modules_per_app,
          discovered_modules: map_size(first_graph.id_to_module),
          edges_count: first_stats.edges_count,
          compile_ms: nil,
          first_build_ms: first_ms,
          second_build_ms: second_ms,
          first_stats: first_stats,
          second_stats: second_stats,
          layer_rule_eval_ms: layer_rules_ms,
          temp_project: tmp_dir
        }
      end)

    if cleanup? do
      File.rm_rf!(tmp_dir)
    end

    results
  end

  defp create_synthetic_umbrella!(tmp_dir, apps, modules_per_app) do
    File.mkdir_p!(Path.join(tmp_dir, "apps"))
    File.mkdir_p!(Path.join(tmp_dir, "config"))
    File.write!(Path.join(tmp_dir, "config/config.exs"), "import Config\n")
    File.write!(Path.join(tmp_dir, "mix.exs"), umbrella_mix_exs())

    app_names =
      1..apps
      |> Enum.map(&String.to_atom("bench_app_#{&1}"))

    Enum.each(app_names, fn app_name ->
      app_dir = Path.join(tmp_dir, "apps/#{app_name}")
      File.mkdir_p!(Path.join(app_dir, "lib"))
      File.write!(Path.join(app_dir, "mix.exs"), app_mix_exs(app_name))
      write_app_modules!(app_dir, app_name, app_names, modules_per_app)
    end)

    File.write!(Path.join(tmp_dir, "arch.exs"), arch_exs(app_names))
  end

  defp write_app_modules!(app_dir, app_name, app_names, modules_per_app) do
    app_index = app_names |> Enum.find_index(&(&1 == app_name)) |> Kernel.+(1)
    app_alias = Macro.camelize(Atom.to_string(app_name))
    app_namespace = "BenchUmbrella.#{app_alias}"

    neighbour_alias =
      case Enum.at(app_names, app_index) do
        nil -> app_name
        neighbour -> neighbour
      end
      |> Atom.to_string()
      |> Macro.camelize()

    Enum.each(1..modules_per_app, fn module_index ->
      previous_index = if module_index == 1, do: modules_per_app, else: module_index - 1

      module_source = """
      defmodule #{app_namespace}.Module#{module_index} do
        alias #{app_namespace}.Module#{previous_index}
        alias BenchUmbrella.#{neighbour_alias}.Module1, as: NeighbourModule

        def run do
          _ = Module#{previous_index}.id()
          _ = NeighbourModule.id()
          id()
        end

        def id, do: {#{app_index}, #{module_index}}
      end
      """

      File.write!(Path.join(app_dir, "lib/module_#{module_index}.ex"), module_source)
    end)
  end

  defp umbrella_mix_exs do
    """
    defmodule BenchUmbrella.MixProject do
      use Mix.Project

      def project do
        [
          apps_path: "apps",
          version: "0.1.0"
        ]
      end
    end
    """
  end

  defp app_mix_exs(app_name) do
    module_name = app_name |> Atom.to_string() |> Macro.camelize()

    """
    defmodule #{module_name}.MixProject do
      use Mix.Project

      def project do
        [
          app: :#{app_name},
          version: "0.1.0",
          build_path: "../../_build",
          config_path: "../../config/config.exs",
          deps_path: "../../deps",
          lockfile: "../../mix.lock",
          elixir: "~> 1.16",
          deps: deps()
        ]
      end

      def application do
        [
          extra_applications: [:logger]
        ]
      end

      defp deps do
        []
      end
    end
    """
  end

  defp arch_exs(app_names) do
    layers =
      app_names
      |> Enum.map(fn app_name ->
        alias_name = app_name |> Atom.to_string() |> Macro.camelize()
        "  layer :#{app_name}, \"BenchUmbrella.#{alias_name}.*\""
      end)
      |> Enum.join("\n")

    forbids =
      app_names
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [from, to] ->
        "  forbid :#{from}, depends_on: [:#{to}]"
      end)
      |> Enum.join("\n")

    """
    layers do
    #{layers}

    #{forbids}
    end
    """
  end

  defp timed(fun) do
    started_at = System.monotonic_time(:millisecond)
    result = fun.()
    elapsed = max(System.monotonic_time(:millisecond) - started_at, 0)

    case result do
      {%Graph{} = graph, stats} when is_map(stats) -> {graph, stats, elapsed}
      other -> {other, elapsed}
    end
  end
end
