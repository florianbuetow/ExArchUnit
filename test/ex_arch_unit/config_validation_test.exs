defmodule ExArchUnit.ConfigValidationTest do
  use ExUnit.Case, async: true

  alias ExArchUnit.Config
  alias ExArchUnit.Rule

  # --- load/1 tuple wrapper ---

  test "load/1 returns {:ok, config} for valid file" do
    assert {:ok, config} = Config.load("fixtures/arch_test.exs")
    assert is_map(config.layers)
  end

  test "load/1 returns {:error, _} for file with invalid DSL" do
    path = "tmp_bad_dsl_#{System.unique_integer([:positive])}.exs"
    File.write!(path, "layer(:web, 123)")

    on_exit(fn -> File.rm(path) end)

    assert {:error, %ArgumentError{}} = Config.load(path)
  end

  # --- validate! error paths ---

  test "validate! raises when layers is not a map" do
    config = %Config{layers: "not a map"}

    assert_raise ArgumentError, ~r/layers must be a map/, fn ->
      Config.validate!(config)
    end
  end

  test "validate! raises when layer selector is not a string" do
    config = %Config{layers: %{web: :not_a_string}}

    assert_raise ArgumentError, ~r/layer selector must be a string/, fn ->
      Config.validate!(config)
    end
  end

  test "validate! raises when layer_rules is not a list" do
    config = %Config{layer_rules: :bad}

    assert_raise ArgumentError, ~r/layer_rules must be a list/, fn ->
      Config.validate!(config)
    end
  end

  test "validate! raises for rule referencing undefined source layer" do
    rule = %Rule{type: :forbid, source: :missing, depends_on: [:web]}
    config = %Config{layers: %{web: "Web.*"}, layer_rules: [rule]}

    assert_raise ArgumentError, ~r/undefined layer :missing/, fn ->
      Config.validate!(config)
    end
  end

  test "validate! raises for rule referencing undefined depends_on layer" do
    rule = %Rule{type: :forbid, source: :web, depends_on: [:missing]}
    config = %Config{layers: %{web: "Web.*"}, layer_rules: [rule]}

    assert_raise ArgumentError, ~r/undefined layer :missing/, fn ->
      Config.validate!(config)
    end
  end

  test "validate! raises for invalid rule struct" do
    config = %Config{layers: %{}, layer_rules: [:not_a_rule]}

    assert_raise ArgumentError, ~r/invalid layer rule/, fn ->
      Config.validate!(config)
    end
  end

  test "validate! raises when include is not a list" do
    config = %Config{include: "not_a_list"}

    assert_raise ArgumentError, ~r/include must be a list/, fn ->
      Config.validate!(config)
    end
  end

  test "validate! raises when include contains non-string" do
    config = %Config{include: [:atom]}

    assert_raise ArgumentError, ~r/include selectors must be strings/, fn ->
      Config.validate!(config)
    end
  end

  test "validate! raises when exclude is not a list" do
    config = %Config{exclude: :bad}

    assert_raise ArgumentError, ~r/exclude must be a list/, fn ->
      Config.validate!(config)
    end
  end

  test "validate! raises when exclude contains non-string" do
    config = %Config{exclude: [123]}

    assert_raise ArgumentError, ~r/exclude selectors must be strings/, fn ->
      Config.validate!(config)
    end
  end

  test "validate! raises when include_deps is not boolean" do
    config = %Config{include_deps: :yes}

    assert_raise ArgumentError, ~r/include_deps must be boolean/, fn ->
      Config.validate!(config)
    end
  end

  test "validate! raises when include_behaviours is not boolean" do
    config = %Config{include_behaviours: "true"}

    assert_raise ArgumentError, ~r/include_behaviours must be boolean/, fn ->
      Config.validate!(config)
    end
  end

  test "validate! raises when cache is not boolean" do
    config = %Config{cache: 1}

    assert_raise ArgumentError, ~r/cache must be boolean/, fn ->
      Config.validate!(config)
    end
  end

  test "validate! raises when builder is not :xref" do
    config = %Config{builder: :other}

    assert_raise ArgumentError, ~r/only :xref builder is supported/, fn ->
      Config.validate!(config)
    end
  end

  test "validate! passes for valid default config" do
    config = %Config{}
    assert %Config{} = Config.validate!(config)
  end
end
