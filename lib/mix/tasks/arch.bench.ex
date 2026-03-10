defmodule Mix.Tasks.Arch.Bench do
  use Mix.Task

  @shortdoc "Run the synthetic umbrella benchmark"

  @moduledoc false

  @doc """
  Runs the synthetic umbrella benchmark.

      mix arch.bench

  Environment variables:
  - `ExArchUnit_BENCH_APPS` (default: 4)
  - `ExArchUnit_BENCH_MODULES_PER_APP` (default: 60)
  - `ExArchUnit_BENCH_KEEP_TMP=1` to keep the generated umbrella project
  """

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    Code.require_file("bench/synthetic_umbrella.exs")
  end
end
