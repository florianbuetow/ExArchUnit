defmodule ExArchUnit.ConfigTest do
  use ExUnit.Case, async: true

  alias ExArchUnit.Config

  test "loads default config when arch file does not exist" do
    config =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        config = Config.load!("test/support/no_file.exs")
        send(self(), {:config, config})
      end)

    assert config =~ "config file not found"

    assert_received {:config, config}
    assert config.layers == %{}
    assert config.layer_rules == []
    assert config.include == []
    assert config.exclude == []
    assert config.include_deps == false
    assert config.include_behaviours == false
    assert config.cache == true
    assert config.builder == :xref
  end

  test "default_config_path/0 returns arch.exs" do
    assert Config.default_config_path() == "arch.exs"
  end

  test "loads and validates DSL config" do
    path = Path.expand("fixtures/arch_test.exs")
    config = Config.load!(path)

    assert config.layers[:bad_domain] == "ExArchFixture.Bad.Domain.*"
    assert config.layers[:bad_web] == "ExArchFixture.Bad.Web.*"
    assert Enum.any?(config.layer_rules, &(&1.type == :forbid))
  end
end
