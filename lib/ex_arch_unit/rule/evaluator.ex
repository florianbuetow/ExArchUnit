defmodule ExArchUnit.Rule.Evaluator do
  @moduledoc """
  Evaluates architecture rules against a dependency graph.

  Provides `forbid/4`, `allow/4`, `assert_no_cycles/3` for ad-hoc rule
  checks, and `evaluate_layer_rules/2` for evaluating all config-defined
  layer rules at once.
  """

  alias ExArchUnit.Config
  alias ExArchUnit.Graph
  alias ExArchUnit.Rule
  alias ExArchUnit.Selector

  @type edge_violation :: {module(), module()}
  @type selector :: String.t() | atom() | [String.t() | atom()]
  @type layer_rule_violation :: %{rule: Rule.t(), violations: [edge_violation()]}

  @selector_cache_key {__MODULE__, :selector_cache}
  @module_name_index_cache_key {__MODULE__, :module_name_index_cache}

  @doc "Returns `:ok` if no source module depends on a target module, or `{:error, violations}`."
  @spec forbid(Graph.t(), Config.t(), selector(), selector()) ::
          :ok | {:error, [edge_violation()]}
  def forbid(%Graph{} = graph, %Config{} = config, source_selector, target_selector) do
    source_ids = resolve_selector(graph, config, source_selector)
    target_ids = resolve_selector(graph, config, target_selector)

    violations =
      source_ids
      |> Enum.sort()
      |> Enum.flat_map(fn source_id ->
        graph
        |> Graph.dependency_ids(source_id)
        |> MapSet.intersection(target_ids)
        |> MapSet.to_list()
        |> Enum.sort()
        |> Enum.map(fn target_id ->
          {Graph.module_for_id(graph, source_id), Graph.module_for_id(graph, target_id)}
        end)
      end)
      |> Enum.uniq()
      |> Graph.sort_edges()

    if violations == [] do
      :ok
    else
      {:error, violations}
    end
  end

  @doc "Returns `:ok` if every dependency of source modules is in the allow-list, or `{:error, violations}`."
  @spec allow(Graph.t(), Config.t(), selector(), selector()) :: :ok | {:error, [edge_violation()]}
  def allow(%Graph{} = graph, %Config{} = config, source_selector, target_selector) do
    source_ids = resolve_selector(graph, config, source_selector)
    allowed_target_ids = resolve_selector(graph, config, target_selector)

    permitted_ids = MapSet.union(source_ids, allowed_target_ids)

    violations =
      source_ids
      |> Enum.sort()
      |> Enum.flat_map(fn source_id ->
        disallowed_targets =
          graph
          |> Graph.dependency_ids(source_id)
          |> Enum.reduce(MapSet.new(), fn target_id, acc ->
            if MapSet.member?(permitted_ids, target_id) do
              acc
            else
              MapSet.put(acc, target_id)
            end
          end)

        disallowed_targets
        |> MapSet.to_list()
        |> Enum.sort()
        |> Enum.map(fn target_id ->
          {Graph.module_for_id(graph, source_id), Graph.module_for_id(graph, target_id)}
        end)
      end)
      |> Enum.uniq()
      |> Graph.sort_edges()

    if violations == [] do
      :ok
    else
      {:error, violations}
    end
  end

  @doc "Returns `:ok` if no cycles exist among the selected modules, or `{:error, cycles}`."
  @spec assert_no_cycles(Graph.t(), Config.t(), keyword()) :: :ok | {:error, [[module()]]}
  def assert_no_cycles(%Graph{} = graph, %Config{} = config, opts) do
    selector =
      Keyword.get(opts, :prefix) ||
        Keyword.get(opts, :in) ||
        raise ArgumentError, "assert_no_cycles expects :prefix or :in option"

    selected_ids = resolve_selector(graph, config, selector)

    cycles =
      graph
      |> Graph.strongly_connected_components(selected_ids)
      |> Enum.map(fn component ->
        component
        |> Enum.map(&Graph.module_for_id(graph, &1))
        |> Enum.sort_by(&Graph.module_name/1)
      end)
      |> Enum.sort_by(fn component -> Enum.map(component, &Graph.module_name/1) end)

    if cycles == [] do
      :ok
    else
      {:error, cycles}
    end
  end

  @doc "Evaluates all layer rules from the config and returns `:ok` or `{:error, violations}`."
  @spec evaluate_layer_rules(Graph.t(), Config.t()) :: :ok | {:error, [layer_rule_violation()]}
  def evaluate_layer_rules(%Graph{} = graph, %Config{} = config) do
    violations =
      config.layer_rules
      |> Enum.flat_map(fn %Rule{} = rule ->
        case rule.type do
          :forbid ->
            case forbid(graph, config, rule.source, rule.depends_on) do
              :ok -> []
              {:error, edges} -> [%{rule: rule, violations: edges}]
            end

          :allow ->
            case allow(graph, config, rule.source, rule.depends_on) do
              :ok -> []
              {:error, edges} -> [%{rule: rule, violations: edges}]
            end
        end
      end)

    if violations == [] do
      :ok
    else
      {:error, violations}
    end
  end

  @doc "Resolves a selector (string, atom, or list) to the set of matching module IDs."
  @spec resolve_selector(Graph.t(), Config.t(), selector()) :: MapSet.t(Graph.module_id())
  def resolve_selector(%Graph{} = graph, %Config{} = config, selector) when is_list(selector) do
    memoized_selector_set(graph, config, selector, fn ->
      Enum.reduce(selector, MapSet.new(), fn current, acc ->
        MapSet.union(acc, resolve_selector(graph, config, current))
      end)
    end)
  end

  def resolve_selector(%Graph{} = graph, %Config{} = config, selector) when is_atom(selector) do
    memoized_selector_set(graph, config, selector, fn ->
      case Map.fetch(config.layers, selector) do
        {:ok, layer_selector} -> resolve_selector(graph, config, layer_selector)
        :error -> resolve_selector(graph, config, Graph.module_name(selector))
      end
    end)
  end

  def resolve_selector(%Graph{} = graph, %Config{} = config, selector) when is_binary(selector) do
    memoized_selector_set(graph, config, selector, fn ->
      compiled_selector = Selector.compile(selector)

      module_name_index(graph)
      |> Enum.reduce(MapSet.new(), fn {module_id, module_name}, acc ->
        if Selector.match?(module_name, compiled_selector) do
          MapSet.put(acc, module_id)
        else
          acc
        end
      end)
    end)
  end

  def resolve_selector(_graph, _config, selector) do
    raise ArgumentError, "unsupported selector #{inspect(selector)}"
  end

  defp memoized_selector_set(%Graph{} = graph, %Config{} = config, selector, resolver) do
    cache_namespace = selector_cache_namespace(graph, config)
    cache_key = {cache_namespace, selector}
    cache = Process.get(@selector_cache_key, %{})

    case Map.fetch(cache, cache_key) do
      {:ok, cached} ->
        cached

      :error ->
        resolved = resolver.()
        Process.put(@selector_cache_key, Map.put(cache, cache_key, resolved))
        resolved
    end
  end

  defp selector_cache_namespace(%Graph{} = graph, %Config{} = config) do
    {:selector_cache, :erlang.phash2(graph.id_to_module), :erlang.phash2(config.layers)}
  end

  defp module_name_index(%Graph{} = graph) do
    cache = Process.get(@module_name_index_cache_key, %{})
    cache_key = :erlang.phash2(graph.id_to_module)

    case Map.fetch(cache, cache_key) do
      {:ok, index} ->
        index

      :error ->
        index =
          graph
          |> Graph.module_ids()
          |> Enum.map(fn module_id ->
            {module_id, graph |> Graph.module_for_id(module_id) |> Graph.module_name()}
          end)

        Process.put(@module_name_index_cache_key, Map.put(cache, cache_key, index))
        index
    end
  end
end
