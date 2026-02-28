defmodule ExArch.Graph do
  @moduledoc """
  Integer-indexed module dependency graph with adjacency-set representation.

  Nodes are modules identified by integer IDs for efficient set operations.
  Edges represent compile-time dependencies extracted from BEAM files.
  """

  defstruct module_to_id: %{},
            id_to_module: %{},
            adjacency: %{}

  @type module_id :: non_neg_integer()

  @type t :: %__MODULE__{
          module_to_id: %{optional(module()) => module_id()},
          id_to_module: %{optional(module_id()) => module()},
          adjacency: %{optional(module_id()) => MapSet.t(module_id())}
        }

  @doc "Builds a graph from a list of modules and `{source, target}` dependency edges."
  @spec from_modules_and_edges([module()], [{module(), module()}]) :: t()
  def from_modules_and_edges(modules, edges) do
    modules =
      modules
      |> Enum.uniq()
      |> Enum.sort()

    module_to_id =
      modules
      |> Enum.with_index()
      |> Map.new(fn {module, id} -> {module, id} end)

    id_to_module =
      module_to_id
      |> Enum.map(fn {module, id} -> {id, module} end)
      |> Map.new()

    adjacency =
      Enum.reduce(Map.keys(id_to_module), %{}, fn id, acc ->
        Map.put(acc, id, MapSet.new())
      end)

    adjacency =
      Enum.reduce(edges, adjacency, fn {source, target}, acc ->
        with {:ok, source_id} <- fetch_module_id(module_to_id, source),
             {:ok, target_id} <- fetch_module_id(module_to_id, target) do
          Map.update!(acc, source_id, &MapSet.put(&1, target_id))
        else
          :error -> acc
        end
      end)

    %__MODULE__{
      module_to_id: module_to_id,
      id_to_module: id_to_module,
      adjacency: adjacency
    }
  end

  @doc "Sorts a list of `{source_module, target_module}` edges deterministically by module name."
  @spec sort_edges([{module(), module()}]) :: [{module(), module()}]
  def sort_edges(edges) do
    Enum.sort_by(edges, fn {source, target} ->
      {module_name(source), module_name(target)}
    end)
  end

  @doc "Returns all modules in the graph, sorted by ID."
  @spec modules(t()) :: [module()]
  def modules(%__MODULE__{id_to_module: id_to_module}) do
    id_to_module
    |> Enum.sort_by(fn {id, _module} -> id end)
    |> Enum.map(fn {_id, module} -> module end)
  end

  @doc "Returns all module IDs in the graph, sorted."
  @spec module_ids(t()) :: [module_id()]
  def module_ids(%__MODULE__{id_to_module: id_to_module}) do
    id_to_module
    |> Map.keys()
    |> Enum.sort()
  end

  @doc "Looks up the integer ID for a module."
  @spec module_id(t(), module()) :: {:ok, module_id()} | :error
  def module_id(%__MODULE__{module_to_id: module_to_id}, module) do
    fetch_module_id(module_to_id, module)
  end

  @doc "Returns the module atom for a given integer ID."
  @spec module_for_id(t(), module_id()) :: module()
  def module_for_id(%__MODULE__{id_to_module: id_to_module}, id) do
    Map.fetch!(id_to_module, id)
  end

  @doc "Returns the set of module IDs that `id` depends on."
  @spec dependency_ids(t(), module_id()) :: MapSet.t(module_id())
  def dependency_ids(%__MODULE__{adjacency: adjacency}, id) do
    Map.get(adjacency, id, MapSet.new())
  end

  @doc ~S'Converts a module atom to its short name (strips the `"Elixir."` prefix).'
  @spec module_name(module()) :: String.t()
  def module_name(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.trim_leading("Elixir.")
  end

  @doc """
  Finds strongly connected components (cycles) among `selected_ids`
  using Kosaraju's algorithm. Returns only non-trivial SCCs.
  """
  @spec strongly_connected_components(t(), MapSet.t(module_id())) :: [[module_id()]]
  def strongly_connected_components(graph, selected_ids) do
    selected_ids = MapSet.new(selected_ids)

    {_visited, order} =
      selected_ids
      |> Enum.sort()
      |> Enum.reduce({MapSet.new(), []}, fn id, {visited, order} ->
        dfs_finish_order(graph, id, selected_ids, visited, order)
      end)

    reverse = reverse_adjacency(graph, selected_ids)

    {_visited, components} =
      order
      |> Enum.reverse()
      |> Enum.reduce({MapSet.new(), []}, fn id, {visited, components} ->
        if MapSet.member?(visited, id) do
          {visited, components}
        else
          {visited, component} = dfs_collect(reverse, id, selected_ids, visited, [])
          {visited, [Enum.sort(component) | components]}
        end
      end)

    components
    |> Enum.filter(fn component ->
      case component do
        [single] -> self_loop?(graph, single)
        many -> length(many) > 1
      end
    end)
    |> Enum.sort_by(fn component ->
      Enum.map(component, fn id -> graph |> module_for_id(id) |> module_name() end)
    end)
  end

  defp dfs_finish_order(graph, id, selected_ids, visited, order) do
    if MapSet.member?(visited, id) or not MapSet.member?(selected_ids, id) do
      {visited, order}
    else
      visited = MapSet.put(visited, id)

      {visited, order} =
        graph
        |> dependency_ids(id)
        |> MapSet.to_list()
        |> Enum.sort()
        |> Enum.reduce({visited, order}, fn dep_id, {visited, order} ->
          if MapSet.member?(selected_ids, dep_id) do
            dfs_finish_order(graph, dep_id, selected_ids, visited, order)
          else
            {visited, order}
          end
        end)

      {visited, [id | order]}
    end
  end

  defp reverse_adjacency(%__MODULE__{} = graph, selected_ids) do
    base =
      selected_ids
      |> MapSet.to_list()
      |> Enum.reduce(%{}, fn id, acc -> Map.put(acc, id, MapSet.new()) end)

    Enum.reduce(selected_ids, base, fn source, acc ->
      source
      |> then(&dependency_ids(graph, &1))
      |> MapSet.to_list()
      |> Enum.reduce(acc, fn target, acc ->
        if MapSet.member?(selected_ids, target) do
          Map.update!(acc, target, &MapSet.put(&1, source))
        else
          acc
        end
      end)
    end)
  end

  defp dfs_collect(reverse, id, selected_ids, visited, acc) do
    if MapSet.member?(visited, id) do
      {visited, acc}
    else
      visited = MapSet.put(visited, id)
      acc = [id | acc]

      reverse
      |> Map.get(id, MapSet.new())
      |> MapSet.to_list()
      |> Enum.sort()
      |> Enum.reduce({visited, acc}, fn dep, {visited, acc} ->
        if MapSet.member?(selected_ids, dep) do
          dfs_collect(reverse, dep, selected_ids, visited, acc)
        else
          {visited, acc}
        end
      end)
    end
  end

  defp self_loop?(graph, id) do
    graph
    |> dependency_ids(id)
    |> MapSet.member?(id)
  end

  defp fetch_module_id(module_to_id, module) do
    case Map.fetch(module_to_id, module) do
      {:ok, id} -> {:ok, id}
      :error -> :error
    end
  end
end
