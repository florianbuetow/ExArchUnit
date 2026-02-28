defmodule ExArch.Config.DSL do
  @moduledoc """
  DSL functions for declaring architecture rules in `arch.exs` config files.

  These functions are imported into the config file at evaluation time.
  They store configuration in the process dictionary and are collected
  into an `ExArch.Config` struct by `collected_config/0`.

  ## Example `arch.exs`

      layers do
        layer :web, "MyAppWeb.*"
        layer :domain, "MyApp.Domain.*"

        allow :web, depends_on: [:domain]
        forbid :domain, depends_on: [:web]
      end

      include "MyApp.*"
      cache true
  """

  alias ExArch.Config
  alias ExArch.Rule

  @store_key {__MODULE__, :config}

  @doc "Resets the process-local config state, optionally to a given `config`."
  @spec reset!(Config.t()) :: :ok
  def reset!(config \\ %Config{}) do
    Process.put(@store_key, config)
    :ok
  end

  @doc "Returns the config accumulated so far in this process."
  @spec collected_config() :: Config.t()
  def collected_config do
    Process.get(@store_key) || %Config{}
  end

  @doc "Executes a block of layer/rule declarations and returns the collected config."
  @spec layers((-> any())) :: Config.t()
  def layers(fun) when is_function(fun, 0) do
    fun.()
    collected_config()
  end

  def layers(opts) when is_list(opts) do
    _ = Keyword.get(opts, :do)
    collected_config()
  end

  @doc "Declares a named layer with the given module selector pattern."
  @spec layer(atom(), String.t()) :: :ok
  def layer(name, selector) when is_atom(name) and is_binary(selector) do
    update(fn config ->
      %{config | layers: Map.put(config.layers, name, selector)}
    end)
  end

  def layer(name, selector) do
    raise ArgumentError,
          "layer/2 expects an atom name and a string selector, got #{inspect({name, selector})}"
  end

  @doc "Declares that `layer_name` is only allowed to depend on the given layers."
  @spec allow(atom(), keyword()) :: :ok
  def allow(layer_name, opts) when is_atom(layer_name) and is_list(opts) do
    add_layer_rule(:allow, layer_name, opts)
  end

  def allow(layer_name, opts) do
    raise ArgumentError,
          "allow/2 expects an atom layer name and keyword options, got #{inspect({layer_name, opts})}"
  end

  @doc "Declares that `layer_name` must not depend on the given layers."
  @spec forbid(atom(), keyword()) :: :ok
  def forbid(layer_name, opts) when is_atom(layer_name) and is_list(opts) do
    add_layer_rule(:forbid, layer_name, opts)
  end

  def forbid(layer_name, opts) do
    raise ArgumentError,
          "forbid/2 expects an atom layer name and keyword options, got #{inspect({layer_name, opts})}"
  end

  @doc "Limits the graph to modules matching the given selector(s)."
  @spec include(String.t() | [String.t()]) :: :ok
  def include(selectors) do
    selectors = normalize_selectors(selectors, "include/1")

    update(fn config ->
      %{config | include: Enum.uniq(config.include ++ selectors)}
    end)
  end

  @doc "Removes modules matching the given selector(s) from the graph."
  @spec exclude(String.t() | [String.t()]) :: :ok
  def exclude(selectors) do
    selectors = normalize_selectors(selectors, "exclude/1")

    update(fn config ->
      %{config | exclude: Enum.uniq(config.exclude ++ selectors)}
    end)
  end

  @doc "When `true`, includes dependency modules from `_build` in the graph."
  @spec include_deps(boolean()) :: :ok
  def include_deps(value) when is_boolean(value) do
    update(fn config -> %{config | include_deps: value} end)
  end

  def include_deps(value) do
    raise ArgumentError, "include_deps/1 expects a boolean, got #{inspect(value)}"
  end

  @doc "When `true`, adds `@behaviour` implementation edges to the graph."
  @spec include_behaviours(boolean()) :: :ok
  def include_behaviours(value) when is_boolean(value) do
    update(fn config -> %{config | include_behaviours: value} end)
  end

  def include_behaviours(value) do
    raise ArgumentError, "include_behaviours/1 expects a boolean, got #{inspect(value)}"
  end

  @doc "When `false`, disables the `:persistent_term` graph cache."
  @spec cache(boolean()) :: :ok
  def cache(value) when is_boolean(value) do
    update(fn config -> %{config | cache: value} end)
  end

  def cache(value) do
    raise ArgumentError, "cache/1 expects a boolean, got #{inspect(value)}"
  end

  @doc "Sets the dependency extraction backend (only `:xref` in v0.1)."
  @spec builder(atom()) :: :ok
  def builder(value) when is_atom(value) do
    update(fn config -> %{config | builder: value} end)
  end

  def builder(value) do
    raise ArgumentError, "builder/1 expects an atom, got #{inspect(value)}"
  end

  defp add_layer_rule(type, layer_name, opts) do
    depends_on =
      opts
      |> Keyword.fetch!(:depends_on)
      |> normalize_depends_on()

    rule = %Rule{type: type, source: layer_name, depends_on: depends_on}

    update(fn config ->
      %{config | layer_rules: config.layer_rules ++ [rule]}
    end)
  end

  defp normalize_depends_on(value) when is_atom(value), do: [value]

  defp normalize_depends_on(values) when is_list(values) do
    if values != [] and Enum.all?(values, &is_atom/1) do
      values
    else
      raise ArgumentError,
            "depends_on must be an atom or non-empty list of atoms, got #{inspect(values)}"
    end
  end

  defp normalize_depends_on(value) do
    raise ArgumentError,
          "depends_on must be an atom or non-empty list of atoms, got #{inspect(value)}"
  end

  defp normalize_selectors(selector, _fn_name) when is_binary(selector), do: [selector]

  defp normalize_selectors(selectors, _fn_name) when is_list(selectors) do
    if Enum.all?(selectors, &is_binary/1) do
      selectors
    else
      raise ArgumentError, "selectors must all be strings, got #{inspect(selectors)}"
    end
  end

  defp normalize_selectors(value, fn_name) do
    raise ArgumentError,
          "#{fn_name} expects a selector string or list of selector strings, got #{inspect(value)}"
  end

  defp update(fun) do
    config = collected_config()
    Process.put(@store_key, fun.(config))
    :ok
  end
end
