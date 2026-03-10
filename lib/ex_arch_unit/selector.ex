defmodule ExArchUnit.Selector do
  @moduledoc """
  Compiles and matches module-name selector patterns.

  Selectors are strings like `"MyApp.Domain.*"` (prefix match) or
  `"MyApp.Domain.User"` (exact match).
  """

  @type compiled :: {:exact, String.t()} | {:prefix, String.t()}

  @doc "Compiles a selector string into a `{:exact, name}` or `{:prefix, prefix}` tuple."
  @spec compile(String.t()) :: compiled()
  def compile(selector) when is_binary(selector) do
    normalized = String.trim_leading(selector, "Elixir.")

    if String.ends_with?(normalized, ".*") do
      prefix = String.trim_trailing(normalized, "*")
      {:prefix, prefix}
    else
      {:exact, normalized}
    end
  end

  @doc "Returns `true` if `module_name` matches the compiled selector."
  @spec match?(String.t(), compiled()) :: boolean()
  def match?(module_name, {:exact, exact}), do: module_name == exact
  def match?(module_name, {:prefix, prefix}), do: String.starts_with?(module_name, prefix)
end
