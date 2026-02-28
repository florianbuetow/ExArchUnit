defmodule ExArch.Config do
  @moduledoc """
  Loads, validates, and represents an ExArchUnit configuration.

  A configuration is typically declared in an `arch.exs` file using the
  `ExArch.Config.DSL` and loaded with `load!/1` or `load/1`.
  """

  alias ExArch.Config.DSL
  alias ExArch.Rule

  @default_config_path "arch.exs"

  defstruct path: nil,
            source_hash: nil,
            layers: %{},
            layer_rules: [],
            include: [],
            exclude: [],
            include_deps: false,
            include_behaviours: false,
            cache: true,
            builder: :xref

  @type t :: %__MODULE__{
          path: String.t(),
          source_hash: String.t(),
          layers: %{optional(atom()) => String.t()},
          layer_rules: [Rule.t()],
          include: [String.t()],
          exclude: [String.t()],
          include_deps: boolean(),
          include_behaviours: boolean(),
          cache: boolean(),
          builder: atom()
        }

  @doc "Returns the default config file path (`\"arch.exs\"`)."
  @spec default_config_path() :: String.t()
  def default_config_path, do: @default_config_path

  @doc """
  Loads and validates the config at `path`, returning `{:ok, config}` or
  `{:error, exception}`.
  """
  @spec load(String.t()) :: {:ok, t()} | {:error, Exception.t()}
  def load(path \\ @default_config_path) do
    {:ok, load!(path)}
  rescue
    error in [RuntimeError, ArgumentError] -> {:error, error}
  end

  @doc """
  Loads and validates the config at `path`, raising on errors.

  If the file does not exist, returns a default config.
  """
  @spec load!(String.t()) :: t()
  def load!(path \\ @default_config_path) do
    config_path = Path.expand(path)

    base_config = %__MODULE__{
      path: config_path,
      source_hash: "missing"
    }

    DSL.reset!(base_config)

    config =
      if File.exists?(config_path) do
        source = File.read!(config_path)
        script = "import ExArch.Config.DSL\n" <> source
        _ = Code.eval_string(script, [], file: config_path)
        %{DSL.collected_config() | path: config_path, source_hash: sha256_file(config_path)}
      else
        IO.warn(
          "ExArchUnit config file not found: #{config_path} — using default (empty) config. " <>
            "Architecture rules from the config file will not be enforced."
        )

        %{
          base_config
          | source_hash: sha256_term({:default_config, config_path})
        }
      end

    validate!(config)
  end

  @doc """
  Validates all fields of `config`, raising `ArgumentError` on invalid values.

  Returns the config unchanged when valid.
  """
  @spec validate!(t()) :: t()
  def validate!(%__MODULE__{} = config) do
    validate_layers!(config.layers)
    validate_layer_rules!(config.layer_rules, config.layers)
    validate_selector_list!(config.include, :include)
    validate_selector_list!(config.exclude, :exclude)

    unless is_boolean(config.include_deps) do
      raise ArgumentError, "include_deps must be boolean, got #{inspect(config.include_deps)}"
    end

    unless is_boolean(config.include_behaviours) do
      raise ArgumentError,
            "include_behaviours must be boolean, got #{inspect(config.include_behaviours)}"
    end

    unless is_boolean(config.cache) do
      raise ArgumentError, "cache must be boolean, got #{inspect(config.cache)}"
    end

    unless config.builder == :xref do
      raise ArgumentError,
            "only :xref builder is supported in v0.1, got #{inspect(config.builder)}"
    end

    config
  end

  @doc "Returns the expanded path of the current working directory."
  @spec project_root() :: String.t()
  def project_root do
    File.cwd!() |> Path.expand()
  end

  defp validate_layers!(layers) when is_map(layers) do
    Enum.each(layers, fn {name, selector} ->
      unless is_atom(name) do
        raise ArgumentError, "layer names must be atoms, got #{inspect(name)}"
      end

      unless is_binary(selector) do
        raise ArgumentError,
              "layer selector must be a string for #{inspect(name)}, got #{inspect(selector)}"
      end
    end)
  end

  defp validate_layers!(value) do
    raise ArgumentError, "layers must be a map, got #{inspect(value)}"
  end

  defp validate_layer_rules!(rules, layers) when is_list(rules) do
    layer_names = Map.keys(layers) |> MapSet.new()

    Enum.each(rules, fn
      %Rule{type: type, source: source, depends_on: deps}
      when type in [:allow, :forbid] and is_atom(source) and is_list(deps) ->
        unless MapSet.member?(layer_names, source) do
          raise ArgumentError, "rule references undefined layer #{inspect(source)}"
        end

        Enum.each(deps, fn dep ->
          unless is_atom(dep) and MapSet.member?(layer_names, dep) do
            raise ArgumentError,
                  "rule #{inspect(type)} #{inspect(source)} depends_on undefined layer #{inspect(dep)}"
          end
        end)

      invalid ->
        raise ArgumentError, "invalid layer rule #{inspect(invalid)}"
    end)
  end

  defp validate_layer_rules!(value, _layers) do
    raise ArgumentError, "layer_rules must be a list, got #{inspect(value)}"
  end

  defp validate_selector_list!(selectors, field) when is_list(selectors) do
    Enum.each(selectors, fn selector ->
      unless is_binary(selector) do
        raise ArgumentError, "#{field} selectors must be strings, got #{inspect(selector)}"
      end
    end)
  end

  defp validate_selector_list!(value, field) do
    raise ArgumentError, "#{field} must be a list of selectors, got #{inspect(value)}"
  end

  defp sha256_file(path) do
    path
    |> File.read!()
    |> sha256_binary()
  end

  defp sha256_term(term) do
    term
    |> :erlang.term_to_binary()
    |> sha256_binary()
  end

  defp sha256_binary(binary) do
    :crypto.hash(:sha256, binary)
    |> Base.encode16(case: :lower)
  end
end
