apps =
  System.get_env("ExArchUnit_BENCH_APPS", "4")
  |> String.to_integer()

modules_per_app =
  System.get_env("ExArchUnit_BENCH_MODULES_PER_APP", "60")
  |> String.to_integer()

cleanup? =
  System.get_env("ExArchUnit_BENCH_KEEP_TMP", "0")
  |> String.downcase()
  |> then(&(&1 not in ["1", "true", "yes"]))

result =
  ExArchUnit.Benchmark.SyntheticUmbrella.run(
    apps: apps,
    modules_per_app: modules_per_app,
    cleanup: cleanup?
  )

IO.puts("ex_arch_unit synthetic umbrella benchmark")
IO.puts("apps=#{result.apps} modules_per_app=#{result.modules_per_app}")
IO.puts("discovered_modules=#{result.discovered_modules} edges=#{result.edges_count}")
IO.puts("first_build_ms=#{result.first_build_ms} cache_hit_build_ms=#{result.second_build_ms}")
IO.puts("layer_rule_eval_ms=#{result.layer_rule_eval_ms}")

unless cleanup? do
  IO.puts("temp_project=#{result.temp_project}")
end
