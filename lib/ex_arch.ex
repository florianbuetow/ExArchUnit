defmodule ExArch do
  @moduledoc """
  ExUnit-first architecture testing helpers for Elixir projects.
  """

  @doc """
  Sets up architecture testing in an ExUnit test module.

  ## Options

    * `:config` — path to the config file (default `"arch.exs"`)
    * `:enforce_config_rules` — whether to enforce layer rules from the config
      file during `setup_all` (default `true`)

  Imports the `forbid/2`, `allow/2`, and `assert_no_cycles/1` macros and
  injects a `setup_all` callback that builds (or reuses) the dependency graph.
  """
  defmacro __using__(opts) do
    config_path = Keyword.get(opts, :config, ExArch.Config.default_config_path())
    enforce_config_rules = Keyword.get(opts, :enforce_config_rules, true)

    quote bind_quoted: [config_path: config_path, enforce_config_rules: enforce_config_rules] do
      import ExArch, only: [forbid: 2, allow: 2, assert_no_cycles: 1]

      @ex_arch_config_path config_path
      @ex_arch_enforce_config_rules enforce_config_rules

      setup_all do
        config = ExArch.Config.load!(@ex_arch_config_path)
        {graph, stats} = ExArch.Graph.Cache.get_or_build(config)

        if @ex_arch_enforce_config_rules do
          ExArch.__assert_config_rules__(graph, config)
        end

        {:ok, graph: graph, arch_stats: stats, arch_config: config}
      end
    end
  end

  @doc """
  Fails when any module matching `source_selector` depends on a module
  matching the `:depends_on` target selector.

  ## Example

      test "domain does not call web" do
        forbid "MyApp.Domain.*", depends_on: "MyAppWeb.*"
      end
  """
  defmacro forbid(source_selector, opts) do
    config_path =
      Module.get_attribute(__CALLER__.module, :ex_arch_config_path) ||
        ExArch.Config.default_config_path()

    quote bind_quoted: [source_selector: source_selector, opts: opts, config_path: config_path] do
      ExArch.__assert_forbid__(binding(), source_selector, opts, config_path)
    end
  end

  @doc """
  Fails when any module matching `source_selector` depends on a module
  *not* matching the `:depends_on` target selector. Dependencies within
  the source set are always permitted (intra-layer references are ok).

  ## Example

      test "web only depends on domain" do
        allow "MyAppWeb.*", depends_on: "MyApp.Domain.*"
      end
  """
  defmacro allow(source_selector, opts) do
    config_path =
      Module.get_attribute(__CALLER__.module, :ex_arch_config_path) ||
        ExArch.Config.default_config_path()

    quote bind_quoted: [source_selector: source_selector, opts: opts, config_path: config_path] do
      ExArch.__assert_allow__(binding(), source_selector, opts, config_path)
    end
  end

  @doc """
  Fails when strongly-connected-component cycles are found among modules
  matching the given selector.

  ## Options

    * `:prefix` — selector string (e.g. `"MyApp.Domain.*"`)
    * `:in` — alias for `:prefix`

  ## Example

      test "domain has no cycles" do
        assert_no_cycles prefix: "MyApp.Domain.*"
      end
  """
  defmacro assert_no_cycles(opts) do
    config_path =
      Module.get_attribute(__CALLER__.module, :ex_arch_config_path) ||
        ExArch.Config.default_config_path()

    quote bind_quoted: [opts: opts, config_path: config_path] do
      ExArch.__assert_no_cycles__(binding(), opts, config_path)
    end
  end

  @doc false
  def __assert_forbid__(binding, source_selector, opts, config_path) do
    target_selector =
      Keyword.get(opts, :depends_on) ||
        raise ArgumentError, "forbid/2 expects :depends_on"

    {graph, config} = resolve_context(binding, config_path)

    case ExArch.Rule.Evaluator.forbid(graph, config, source_selector, target_selector) do
      :ok ->
        :ok

      {:error, violations} ->
        ExUnit.Assertions.flunk(
          ExArch.Reporter.format_forbid(source_selector, target_selector, violations)
        )
    end
  end

  @doc false
  def __assert_allow__(binding, source_selector, opts, config_path) do
    target_selector =
      Keyword.get(opts, :depends_on) ||
        raise ArgumentError, "allow/2 expects :depends_on"

    {graph, config} = resolve_context(binding, config_path)

    case ExArch.Rule.Evaluator.allow(graph, config, source_selector, target_selector) do
      :ok ->
        :ok

      {:error, violations} ->
        ExUnit.Assertions.flunk(
          ExArch.Reporter.format_allow(source_selector, target_selector, violations)
        )
    end
  end

  @doc false
  def __assert_no_cycles__(binding, opts, config_path) do
    selector = Keyword.get(opts, :prefix) || Keyword.get(opts, :in)

    unless selector do
      raise ArgumentError, "assert_no_cycles/1 expects :prefix or :in option"
    end

    {graph, config} = resolve_context(binding, config_path)

    case ExArch.Rule.Evaluator.assert_no_cycles(graph, config, opts) do
      :ok -> :ok
      {:error, cycles} -> ExUnit.Assertions.flunk(ExArch.Reporter.format_cycles(selector, cycles))
    end
  end

  @doc false
  def __assert_config_rules__(graph, config) do
    case ExArch.Rule.Evaluator.evaluate_layer_rules(graph, config) do
      :ok ->
        :ok

      {:error, layer_rule_violations} ->
        ExUnit.Assertions.flunk(ExArch.Reporter.format_layer_rules(layer_rule_violations))
    end
  end

  defp resolve_context(binding, config_path) do
    context = binding[:context] || binding[:_context] || %{}

    case context do
      %{graph: graph, arch_config: config} ->
        {graph, config}

      _ ->
        config = ExArch.Config.load!(config_path)
        {graph, _stats} = ExArch.Graph.Cache.get_or_build(config)
        {graph, config}
    end
  end
end
