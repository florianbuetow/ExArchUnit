defmodule ExArch.Reporter do
  @moduledoc """
  Formats architecture rule violations into human-readable messages
  for ExUnit assertion output.
  """

  alias ExArch.Graph
  alias ExArch.Rule.Evaluator

  @doc "Formats a forbid-rule violation message listing offending dependencies."
  @spec format_forbid(term(), term(), [{module(), module()}]) :: String.t()
  def format_forbid(source_selector, target_selector, violations) do
    lines =
      violations
      |> Enum.map(fn {source, target} ->
        "  #{Graph.module_name(source)} -> #{Graph.module_name(target)}"
      end)
      |> Enum.join("\n")

    """
    Architecture rule violated:
      forbid #{inspect(source_selector)}, depends_on: #{inspect(target_selector)}

    Violations (#{length(violations)}):
    #{lines}
    """
  end

  @doc "Formats an allow-rule violation message listing disallowed dependencies."
  @spec format_allow(term(), term(), [{module(), module()}]) :: String.t()
  def format_allow(source_selector, target_selector, violations) do
    lines =
      violations
      |> Enum.map(fn {source, target} ->
        "  #{Graph.module_name(source)} -> #{Graph.module_name(target)}"
      end)
      |> Enum.join("\n")

    """
    Architecture rule violated:
      allow #{inspect(source_selector)}, depends_on: #{inspect(target_selector)}

    Disallowed dependencies (#{length(violations)}):
    #{lines}
    """
  end

  @doc "Formats a cycle-detection violation message listing each cycle."
  @spec format_cycles(term(), [[module()]]) :: String.t()
  def format_cycles(selector, cycles) do
    lines =
      cycles
      |> Enum.map(fn modules ->
        sorted = Enum.sort_by(modules, &Graph.module_name/1)
        names = Enum.map(sorted, &Graph.module_name/1)
        "  " <> Enum.join(names ++ [hd(names)], " -> ")
      end)
      |> Enum.join("\n")

    """
    Architecture rule violated:
      assert_no_cycles #{inspect(selector)}

    Cycles (#{length(cycles)}):
    #{lines}
    """
  end

  @doc "Formats config-level layer rule violations into a combined message."
  @spec format_layer_rules([Evaluator.layer_rule_violation()]) :: String.t()
  def format_layer_rules(layer_rule_violations) do
    sections =
      layer_rule_violations
      |> Enum.map(fn %{rule: rule, violations: violations} ->
        lines =
          violations
          |> Enum.map(fn {source, target} ->
            "    #{Graph.module_name(source)} -> #{Graph.module_name(target)}"
          end)
          |> Enum.join("\n")

        """
          #{rule.type} #{inspect(rule.source)}, depends_on: #{inspect(rule.depends_on)}
        #{lines}
        """
      end)
      |> Enum.join("\n")

    """
    Architecture config rules violated:

    #{sections}
    """
  end
end
