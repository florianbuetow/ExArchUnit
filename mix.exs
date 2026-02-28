defmodule ExArchUnit.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_arch_unit,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [
        ignore_modules: [
          ExArch.Benchmark.SyntheticUmbrella,
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
        extras: ["README.md", "CHANGELOG.md"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :tools]
    ]
  end

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
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end
end
