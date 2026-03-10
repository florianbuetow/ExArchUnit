defmodule ExArchUnit.Graph.Cache do
  @moduledoc """
  `:persistent_term`-backed cache for the dependency graph.

  The cache is keyed by project identity and invalidated when config content,
  BEAM file mtimes, or filter options change.
  """

  alias ExArchUnit.Config
  alias ExArchUnit.Graph.Builder

  @keys_entry {__MODULE__, :keys}

  @type stats :: Builder.stats()

  @doc "Returns the cached graph or builds a fresh one if the cache is stale."
  @spec get_or_build(Config.t()) :: {ExArchUnit.Graph.t(), stats()}
  def get_or_build(%Config{} = config) do
    if no_cache?(config) do
      Builder.build(config)
    else
      key = cache_key(config)
      entry_key = entry_key(key)
      fingerprint = fingerprint(config)

      case :persistent_term.get(entry_key, :missing) do
        %{fingerprint: ^fingerprint, graph: graph, stats: stats} ->
          {graph, Map.put(stats, :cache_hit?, true)}

        _ ->
          :global.trans({__MODULE__, key}, fn ->
            case :persistent_term.get(entry_key, :missing) do
              %{fingerprint: ^fingerprint, graph: graph, stats: stats} ->
                {graph, Map.put(stats, :cache_hit?, true)}

              _ ->
                {graph, stats} = Builder.build(config)

                entry = %{
                  graph: graph,
                  fingerprint: fingerprint,
                  stats: Map.put(stats, :cache_hit?, false)
                }

                :persistent_term.put(entry_key, entry)
                remember_key(entry_key)
                {graph, Map.put(stats, :cache_hit?, false)}
            end
          end)
      end
    end
  end

  @doc "Erases all cached graph entries from `:persistent_term`."
  @spec clear() :: :ok
  def clear do
    :persistent_term.get(@keys_entry, [])
    |> Enum.each(&:persistent_term.erase/1)

    :persistent_term.erase(@keys_entry)
    :ok
  end

  defp no_cache?(%Config{} = config) do
    (System.get_env("ExArchUnit_NO_CACHE") || "")
    |> String.downcase()
    |> then(&(&1 in ["1", "true", "yes"]))
    |> Kernel.or(not config.cache)
  end

  defp cache_key(_config) do
    {
      Mix.env(),
      Config.project_root(),
      Mix.Project.build_path() |> Path.expand(),
      Builder.project_apps()
    }
  end

  defp fingerprint(%Config{} = config) do
    dirs =
      config
      |> Builder.discover_ebin_dirs()
      |> Enum.map(&dir_fingerprint/1)
      |> Enum.sort()

    %{
      arch_hash: config.source_hash,
      dir_fingerprint: dirs,
      include: config.include,
      exclude: config.exclude,
      include_deps: config.include_deps,
      include_behaviours: config.include_behaviours
    }
  end

  defp dir_fingerprint(dir) do
    beams =
      dir
      |> Path.join("*.beam")
      |> Path.wildcard()
      |> Enum.sort()

    {max_mtime, count, stat_hash} =
      Enum.reduce(beams, {0, 0, 0}, fn beam, {current_max, count, stat_hash} ->
        case File.stat(beam, time: :posix) do
          {:ok, stat} ->
            file_hash = :erlang.phash2({Path.basename(beam), stat.mtime, stat.size})
            {max(current_max, stat.mtime), count + 1, :erlang.phash2({stat_hash, file_hash})}

          {:error, _reason} ->
            {current_max, count, stat_hash}
        end
      end)

    {dir, max_mtime, count, stat_hash}
  end

  defp entry_key(key), do: {__MODULE__, key}

  defp remember_key(entry_key) do
    keys = :persistent_term.get(@keys_entry, [])

    unless entry_key in keys do
      :persistent_term.put(@keys_entry, [entry_key | keys])
    end
  end
end
