defmodule ExArchUnit.Graph.Builder do
  @moduledoc """
  Builds an `ExArchUnit.Graph` from compiled BEAM files using `:xref`.

  Discovers ebin directories, loads modules into an isolated xref server,
  extracts call edges (and optionally `@behaviour` edges), then applies
  include/exclude filters from the config.
  """
  @compile {:no_warn_undefined, :xref}

  alias ExArchUnit.Config
  alias ExArchUnit.Graph
  alias ExArchUnit.Selector

  @type stats :: %{
          total_ms: non_neg_integer(),
          discover_beams_ms: non_neg_integer(),
          xref_load_ms: non_neg_integer(),
          extract_edges_ms: non_neg_integer(),
          normalize_ms: non_neg_integer(),
          modules_count: non_neg_integer(),
          edges_count: non_neg_integer(),
          cache_hit?: boolean()
        }

  @doc "Builds a dependency graph and returns `{graph, stats}` with timing information."
  @spec build(Config.t()) :: {Graph.t(), stats()}
  def build(%Config{} = config) do
    total_started_at = now_ms()

    {ebin_dirs, discover_dirs_ms} = timed_ms(fn -> discover_ebin_dirs(config) end)
    {beam_files, discover_beams_ms} = timed_ms(fn -> discover_beam_files(ebin_dirs) end)

    if beam_files == [] do
      raise RuntimeError, "No BEAMs found; run `mix test` or `mix compile`."
    end

    {modules, edges, xref_load_ms, extract_edges_ms} =
      load_edges_via_xref!(ebin_dirs, beam_files, config.include_behaviours)

    {graph, normalize_ms} =
      timed_ms(fn ->
        build_graph(config, modules, edges)
      end)

    stats = %{
      total_ms: max(now_ms() - total_started_at, 0),
      discover_beams_ms: discover_dirs_ms + discover_beams_ms,
      xref_load_ms: xref_load_ms,
      extract_edges_ms: extract_edges_ms,
      normalize_ms: normalize_ms,
      modules_count: map_size(graph.id_to_module),
      edges_count: graph_edge_count(graph),
      cache_hit?: false
    }

    maybe_profile!(stats)
    {graph, stats}
  end

  @doc "Returns the list of ebin directories to analyze based on the config."
  @spec discover_ebin_dirs(Config.t()) :: [String.t()]
  def discover_ebin_dirs(%Config{} = config) do
    build_path = Mix.Project.build_path() |> Path.expand()

    dirs =
      cond do
        config.include_deps ->
          Path.wildcard(Path.join([build_path, "lib", "*", "ebin"]))

        Mix.Project.umbrella?() ->
          project_apps()
          |> Enum.map(fn app ->
            Path.join([build_path, "lib", Atom.to_string(app), "ebin"])
          end)

        true ->
          app =
            Mix.Project.config()[:app] ||
              raise RuntimeError, "Unable to determine Mix project app name for BEAM discovery"

          [Path.join([build_path, "lib", Atom.to_string(app), "ebin"])]
      end

    dirs
    |> Enum.filter(&File.dir?/1)
    |> Enum.sort()
  end

  @doc "Returns the list of application atoms for the current project (umbrella-aware)."
  @spec project_apps() :: [atom()]
  def project_apps do
    if Mix.Project.umbrella?() do
      apps_paths()
      |> Map.keys()
      |> Enum.sort()
      |> case do
        [] -> discover_umbrella_apps_from_filesystem(Config.project_root())
        apps -> apps
      end
    else
      [Mix.Project.config()[:app]]
    end
  end

  @doc "Fallback discovery of umbrella apps by scanning `apps/*/mix.exs` on disk."
  @spec discover_umbrella_apps_from_filesystem(String.t()) :: [atom()]
  def discover_umbrella_apps_from_filesystem(project_root) do
    project_root
    |> Path.join("apps/*/mix.exs")
    |> Path.wildcard()
    |> Enum.map(fn mix_file ->
      mix_file
      |> Path.dirname()
      |> Path.basename()
      |> String.to_atom()
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp apps_paths do
    if function_exported?(Mix.Project, :apps_paths, 0) do
      try do
        Mix.Project.apps_paths()
      rescue
        e in [Mix.Error, UndefinedFunctionError] ->
          IO.warn(
            "ExArchUnit: Mix.Project.apps_paths() failed (#{Exception.message(e)}), " <>
              "falling back to filesystem discovery"
          )

          %{}
      end
    else
      %{}
    end
  end

  defp discover_beam_files(ebin_dirs) do
    ebin_dirs
    |> Enum.flat_map(fn dir ->
      Path.wildcard(Path.join(dir, "*.beam"))
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp load_edges_via_xref!(ebin_dirs, beam_files, include_behaviours) do
    {:ok, _started} = Application.ensure_all_started(:tools)
    {:ok, xref_server} = :xref.start([{:xref_mode, :modules}])
    :ok = :xref.set_default(xref_server, [{:warnings, false}, {:verbose, false}])

    try do
      xref_load_started_at = now_ms()

      Enum.each(ebin_dirs, fn dir ->
        case :xref.add_directory(xref_server, String.to_charlist(dir), [
               {:warnings, false},
               {:verbose, false}
             ]) do
          {:ok, _modules} ->
            :ok

          {:error, _module, reason} ->
            raise RuntimeError, "xref add_directory failed for #{dir}: #{inspect(reason)}"
        end
      end)

      xref_load_ms = max(now_ms() - xref_load_started_at, 0)
      extract_started_at = now_ms()

      {:ok, modules} = :xref.q(xref_server, ~c"AM")
      {:ok, call_edges} = :xref.q(xref_server, ~c"ME")

      behaviour_edges =
        if include_behaviours do
          extract_behaviour_edges(beam_files, MapSet.new(modules))
        else
          []
        end

      edges =
        (call_edges ++ behaviour_edges)
        |> Enum.uniq()
        |> Graph.sort_edges()

      extract_edges_ms = max(now_ms() - extract_started_at, 0)
      {modules, edges, xref_load_ms, extract_edges_ms}
    after
      :xref.stop(xref_server)
    end
  end

  defp extract_behaviour_edges(beam_files, analyzed_modules) do
    beam_files
    |> Enum.flat_map(fn beam_file ->
      case :beam_lib.chunks(String.to_charlist(beam_file), [:attributes]) do
        {:ok, {module, [attributes: attributes]}} ->
          attributes
          |> extract_behaviours_from_attributes()
          |> Enum.filter(fn behaviour_module ->
            MapSet.member?(analyzed_modules, module) and
              MapSet.member?(analyzed_modules, behaviour_module)
          end)
          |> Enum.map(fn behaviour_module -> {module, behaviour_module} end)

        _ ->
          []
      end
    end)
  end

  defp extract_behaviours_from_attributes(attributes) do
    behaviour_entries =
      Keyword.get_values(attributes, :behaviour) ++ Keyword.get_values(attributes, :behavior)

    behaviour_entries
    |> List.flatten()
    |> Enum.filter(&is_atom/1)
  end

  defp build_graph(config, modules, edges) do
    selected_modules = apply_module_filters(modules, config)
    selected_set = MapSet.new(selected_modules)

    filtered_edges =
      edges
      |> Enum.filter(fn {source, target} ->
        MapSet.member?(selected_set, source) and MapSet.member?(selected_set, target)
      end)
      |> Enum.uniq()
      |> Graph.sort_edges()

    Graph.from_modules_and_edges(selected_modules, filtered_edges)
  end

  defp apply_module_filters(modules, %Config{} = config) do
    compiled_include = Enum.map(config.include, &Selector.compile/1)
    compiled_exclude = Enum.map(config.exclude, &Selector.compile/1)

    modules
    |> Enum.uniq()
    |> Enum.sort()
    |> then(fn list ->
      if compiled_include == [] do
        list
      else
        Enum.filter(list, fn module ->
          module_name = Graph.module_name(module)
          Enum.any?(compiled_include, &Selector.match?(module_name, &1))
        end)
      end
    end)
    |> Enum.reject(fn module ->
      module_name = Graph.module_name(module)
      Enum.any?(compiled_exclude, &Selector.match?(module_name, &1))
    end)
    |> Enum.sort()
  end

  defp graph_edge_count(%Graph{} = graph) do
    graph.adjacency
    |> Map.values()
    |> Enum.reduce(0, fn deps, acc -> acc + MapSet.size(deps) end)
  end

  defp maybe_profile!(stats) do
    profile_val = (System.get_env("ExArchUnit_PROFILE") || "") |> String.downcase()

    if profile_val in ["1", "true", "yes"] do
      IO.puts("[ex_arch_unit] graph stats: #{inspect(stats)}")
    end
  end

  defp timed_ms(fun) do
    started_at = now_ms()
    result = fun.()
    {result, max(now_ms() - started_at, 0)}
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
