defmodule ExArchUnit.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_arch_unit,
      version: "0.1.0",
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [
        ignore_modules: [
          ExArchUnit.Benchmark.SyntheticUmbrella,
          Mix.Tasks.Arch.Bench,
          Mix.Tasks.Arch.Check,
          ExArchFixture.Bad.Domain.Service,
          ExArchFixture.Bad.Web.Endpoint,
          ExArchFixture.Behaviour.Contract,
          ExArchFixture.Behaviour.Impl,
          ExArchFixture.Cycle.A,
          ExArchFixture.Cycle.B,
          ExArchFixture.Ok.Domain.Service,
          ExArchFixture.Ok.Web.Controller,
          ExArchFixture.Smoke.A,
          ExArchFixture.Smoke.B
        ]
      ],
      description:
        "Enforce architecture rules in Elixir projects — without touching production code. " <>
          "Define layer boundaries in arch.exs, run mix arch.check, and get CI-friendly violations.",
      package: package(),
      homepage_url: "https://github.com/florianbuetow/ExArchUnit",
      source_url: "https://github.com/florianbuetow/ExArchUnit",
      docs: [
        source_ref: "v0.1.0",
        source_url: "https://github.com/florianbuetow/ExArchUnit",
        main: "readme",
        extras: ["README.md", "CHANGELOG.md", "LICENSE"],
        skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/florianbuetow/ExArchUnit"
      },
      files: ~w(
        lib/ex_arch_unit.ex
        lib/ex_arch_unit
        lib/mix/tasks/arch.check.ex
        mix.exs
        README.md
        LICENSE
        CHANGELOG.md
      ),
      exclude_patterns: [~r/benchmark/]
    ]
  end
end
