defmodule ExArch.UmbrellaIntegrationTest do
  use ExUnit.Case, async: false

  alias ExArch.Config
  alias ExArch.Graph.Builder
  alias ExArch.Rule.Evaluator

  @moduletag :umbrella

  test "discovers umbrella apps and evaluates rules against compiled umbrella beams" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "ex_arch_umbrella_#{System.unique_integer([:positive])}")

    File.rm_rf!(tmp_dir)
    create_umbrella_fixture!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {compile_out, compile_exit} =
      System.cmd("mix", ["compile"],
        cd: tmp_dir,
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    assert compile_exit == 0, compile_out

    :ok =
      Mix.Project.in_project(:umbrella_fixture, tmp_dir, fn _ ->
        config =
          Config.load!(Path.join(tmp_dir, "arch.exs"))
          |> Map.put(:cache, false)
          |> Map.put(:include, ["UmbrellaFixture.*"])

        ebin_dirs = Builder.discover_ebin_dirs(config)
        assert Enum.any?(ebin_dirs, &String.ends_with?(&1, "/_build/test/lib/app_a/ebin"))
        assert Enum.any?(ebin_dirs, &String.ends_with?(&1, "/_build/test/lib/app_b/ebin"))

        {graph, _stats} = Builder.build(config)

        assert {:error, rule_violations} = Evaluator.evaluate_layer_rules(graph, config)

        assert Enum.any?(rule_violations, fn %{violations: edges} ->
                 Enum.any?(edges, fn {source, target} ->
                   ExArch.Graph.module_name(source) == "UmbrellaFixture.AppA.Service" and
                     ExArch.Graph.module_name(target) == "UmbrellaFixture.AppB.Repository"
                 end)
               end)

        :ok
      end)
  end

  defp create_umbrella_fixture!(tmp_dir) do
    File.mkdir_p!(tmp_dir)
    File.mkdir_p!(Path.join(tmp_dir, "apps/app_a/lib"))
    File.mkdir_p!(Path.join(tmp_dir, "apps/app_b/lib"))
    File.mkdir_p!(Path.join(tmp_dir, "config"))

    File.write!(Path.join(tmp_dir, "mix.exs"), umbrella_mix_exs())
    File.write!(Path.join(tmp_dir, "config/config.exs"), "import Config\n")
    File.write!(Path.join(tmp_dir, "apps/app_a/mix.exs"), app_mix_exs(:app_a))
    File.write!(Path.join(tmp_dir, "apps/app_b/mix.exs"), app_mix_exs(:app_b))

    File.write!(Path.join(tmp_dir, "apps/app_a/lib/service.ex"), app_a_module())
    File.write!(Path.join(tmp_dir, "apps/app_b/lib/repository.ex"), app_b_module())
    File.write!(Path.join(tmp_dir, "arch.exs"), umbrella_arch_exs())
  end

  defp umbrella_mix_exs do
    """
    defmodule UmbrellaFixture.MixProject do
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

  defp app_mix_exs(app) do
    app_name = Atom.to_string(app)
    module_name = app_name |> Macro.camelize()

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

  defp app_a_module do
    """
    defmodule UmbrellaFixture.AppA.Service do
      alias UmbrellaFixture.AppB.Repository

      def run do
        Repository.fetch()
      end
    end
    """
  end

  defp app_b_module do
    """
    defmodule UmbrellaFixture.AppB.Repository do
      def fetch, do: :ok
    end
    """
  end

  defp umbrella_arch_exs do
    """
    layers do
      layer :app_a, "UmbrellaFixture.AppA.*"
      layer :app_b, "UmbrellaFixture.AppB.*"

      forbid :app_a, depends_on: [:app_b]
    end
    """
  end
end
