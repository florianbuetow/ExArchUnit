defmodule ExArchUnit.Config.DSLTest do
  use ExUnit.Case, async: true

  alias ExArchUnit.Config
  alias ExArchUnit.Config.DSL

  setup do
    DSL.reset!()
    :ok
  end

  # --- layer/2 ---

  test "layer/2 accepts atom name and string selector" do
    DSL.layer(:web, "MyApp.Web.*")
    config = DSL.collected_config()
    assert config.layers == %{web: "MyApp.Web.*"}
  end

  test "layer/2 raises on non-atom name" do
    assert_raise ArgumentError, fn -> DSL.layer("web", "MyApp.*") end
  end

  test "layer/2 raises on non-string selector" do
    assert_raise ArgumentError, fn -> DSL.layer(:web, :bad) end
  end

  # --- allow/2 and forbid/2 ---

  test "allow/2 adds a layer rule" do
    DSL.layer(:web, "Web.*")
    DSL.layer(:domain, "Domain.*")
    DSL.allow(:web, depends_on: [:domain])
    config = DSL.collected_config()
    assert length(config.layer_rules) == 1
    assert hd(config.layer_rules).type == :allow
  end

  test "forbid/2 adds a layer rule" do
    DSL.layer(:web, "Web.*")
    DSL.layer(:domain, "Domain.*")
    DSL.forbid(:domain, depends_on: [:web])
    config = DSL.collected_config()
    assert hd(config.layer_rules).type == :forbid
  end

  test "allow/2 raises on non-atom layer name" do
    assert_raise ArgumentError, fn -> DSL.allow("web", depends_on: [:domain]) end
  end

  test "forbid/2 raises on non-atom layer name" do
    assert_raise ArgumentError, fn -> DSL.forbid("domain", depends_on: [:web]) end
  end

  test "allow/2 raises when depends_on is missing" do
    DSL.layer(:web, "Web.*")
    assert_raise KeyError, fn -> DSL.allow(:web, []) end
  end

  test "forbid/2 raises when depends_on is missing" do
    DSL.layer(:domain, "Domain.*")
    assert_raise KeyError, fn -> DSL.forbid(:domain, []) end
  end

  test "forbid/2 with depends_on: [] raises ArgumentError" do
    DSL.layer(:domain, "Domain.*")
    assert_raise ArgumentError, fn -> DSL.forbid(:domain, depends_on: []) end
  end

  test "depends_on with non-atom list raises ArgumentError" do
    DSL.layer(:web, "Web.*")
    assert_raise ArgumentError, fn -> DSL.allow(:web, depends_on: ["domain"]) end
  end

  test "depends_on with single atom wraps into list" do
    DSL.layer(:web, "Web.*")
    DSL.layer(:domain, "Domain.*")
    DSL.allow(:web, depends_on: :domain)
    config = DSL.collected_config()
    assert hd(config.layer_rules).depends_on == [:domain]
  end

  # --- include/1 and exclude/1 ---

  test "include/1 with a single string" do
    DSL.include("MyApp.*")
    assert DSL.collected_config().include == ["MyApp.*"]
  end

  test "include/1 with a list of strings" do
    DSL.include(["MyApp.*", "Other.*"])
    assert DSL.collected_config().include == ["MyApp.*", "Other.*"]
  end

  test "include/1 raises on list with non-string" do
    assert_raise ArgumentError, fn -> DSL.include([:atom]) end
  end

  test "include/1 raises on non-string non-list" do
    assert_raise ArgumentError, fn -> DSL.include(123) end
  end

  test "exclude/1 with a single string" do
    DSL.exclude("Legacy.*")
    assert DSL.collected_config().exclude == ["Legacy.*"]
  end

  test "exclude/1 with a list of strings" do
    DSL.exclude(["Legacy.*", "Old.*"])
    assert DSL.collected_config().exclude == ["Legacy.*", "Old.*"]
  end

  test "exclude/1 raises on non-string" do
    assert_raise ArgumentError, fn -> DSL.exclude(:bad) end
  end

  test "exclude/1 raises on list with non-string" do
    assert_raise ArgumentError, fn -> DSL.exclude([:atom]) end
  end

  # --- include_deps/1, include_behaviours/1, cache/1 ---

  test "include_deps/1 sets boolean" do
    DSL.include_deps(true)
    assert DSL.collected_config().include_deps == true
  end

  test "include_deps/1 raises on non-boolean" do
    assert_raise ArgumentError, fn -> DSL.include_deps(:yes) end
  end

  test "include_behaviours/1 sets boolean" do
    DSL.include_behaviours(true)
    assert DSL.collected_config().include_behaviours == true
  end

  test "include_behaviours/1 raises on non-boolean" do
    assert_raise ArgumentError, fn -> DSL.include_behaviours("true") end
  end

  test "cache/1 sets boolean" do
    DSL.cache(false)
    assert DSL.collected_config().cache == false
  end

  test "cache/1 raises on non-boolean" do
    assert_raise ArgumentError, fn -> DSL.cache(1) end
  end

  # --- builder/1 ---

  test "builder/1 sets atom" do
    DSL.builder(:xref)
    assert DSL.collected_config().builder == :xref
  end

  test "builder/1 raises on non-atom" do
    assert_raise ArgumentError, fn -> DSL.builder("xref") end
  end

  # --- collected_config/0 fallback ---

  test "collected_config/0 returns default Config when process dict is empty" do
    Process.delete({ExArchUnit.Config.DSL, :config})
    config = DSL.collected_config()
    assert %Config{} = config
    assert config.layers == %{}
  end

  # --- layers/1 block form ---

  test "layers/1 function form collects config" do
    result =
      DSL.layers(fn ->
        DSL.layer(:web, "Web.*")
      end)

    assert result.layers == %{web: "Web.*"}
  end

  test "layers/1 keyword form returns collected config" do
    DSL.layer(:web, "Web.*")
    result = DSL.layers(do: nil)
    assert result.layers == %{web: "Web.*"}
  end

  # --- normalize_depends_on non-atom non-list ---

  test "depends_on with non-atom non-list raises ArgumentError" do
    DSL.layer(:web, "Web.*")
    assert_raise ArgumentError, fn -> DSL.allow(:web, depends_on: 123) end
  end
end
