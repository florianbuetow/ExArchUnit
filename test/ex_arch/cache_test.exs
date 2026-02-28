defmodule ExArch.CacheTest do
  use ExUnit.Case, async: false

  alias ExArch.Config
  alias ExArch.Graph.Builder
  alias ExArch.Graph.Cache

  setup do
    Cache.clear()
    :ok
  end

  test "cache hit occurs on second build when fingerprint is unchanged" do
    config =
      Config.load!("fixtures/arch_test.exs")
      |> Map.put(:include, ["ExArchFixture.Bad.*"])

    {_graph, stats_first} = Cache.get_or_build(config)
    {_graph, stats_second} = Cache.get_or_build(config)

    assert stats_first.cache_hit? == false
    assert stats_second.cache_hit? == true
  end

  test "cache invalidates when config file content changes" do
    tmp_config_path =
      Path.join(System.tmp_dir!(), "ex_arch_cache_test_#{System.unique_integer([:positive])}.exs")

    File.write!(tmp_config_path, "layers do\n  layer :one, \"ExArchFixture.Bad.*\"\nend\n")

    config = Config.load!(tmp_config_path)

    {_graph, stats_first} = Cache.get_or_build(config)
    assert stats_first.cache_hit? == false

    File.write!(
      tmp_config_path,
      "layers do\n  layer :one, \"ExArchFixture.Bad.*\"\n  layer :two, \"ExArchFixture.Cycle.*\"\nend\n"
    )

    updated_config = Config.load!(tmp_config_path)
    {_graph, stats_second} = Cache.get_or_build(updated_config)

    assert stats_second.cache_hit? == false
  end

  test "cache invalidates when BEAM mtimes change in analyzed ebin dirs" do
    config =
      Config.load!("fixtures/arch_test.exs")
      |> Map.put(:include, ["ExArchFixture.Ok.*"])

    {_graph, stats_first} = Cache.get_or_build(config)
    {_graph, stats_second} = Cache.get_or_build(config)

    assert stats_first.cache_hit? == false
    assert stats_second.cache_hit? == true

    beam_file =
      config
      |> Builder.discover_ebin_dirs()
      |> Enum.flat_map(&Path.wildcard(Path.join(&1, "*.beam")))
      |> List.first()

    assert is_binary(beam_file)

    touch_time =
      DateTime.utc_now()
      |> DateTime.add(5, :second)
      |> DateTime.to_naive()
      |> NaiveDateTime.to_erl()

    File.touch!(beam_file, touch_time)

    {_graph, stats_third} = Cache.get_or_build(config)
    assert stats_third.cache_hit? == false
  end
end
