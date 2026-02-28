defmodule Mix.Tasks.Arch.CheckTest do
  use ExUnit.Case, async: false

  alias ExArch.Graph.Cache

  setup do
    Cache.clear()
    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    saved_no_cache = System.get_env("ExArch_NO_CACHE")
    saved_profile = System.get_env("ExArch_PROFILE")

    on_exit(fn ->
      Mix.shell(previous_shell)

      if saved_no_cache,
        do: System.put_env("ExArch_NO_CACHE", saved_no_cache),
        else: System.delete_env("ExArch_NO_CACHE")

      if saved_profile,
        do: System.put_env("ExArch_PROFILE", saved_profile),
        else: System.delete_env("ExArch_PROFILE")
    end)

    :ok
  end

  test "passing config prints success message" do
    Mix.Tasks.Arch.Check.run(["--config", "fixtures/arch_ok.exs"])

    assert_received {:mix_shell, :info, [msg]}
    assert msg =~ "All architecture rules passed."
  end

  test "violating config raises Mix.Error with violation details" do
    assert_raise Mix.Error, ~r/Architecture rules violated/, fn ->
      Mix.Tasks.Arch.Check.run(["--config", "fixtures/arch_test.exs"])
    end

    assert_received {:mix_shell, :error, [msg]}
    assert msg =~ "Architecture config rules violated"
  end

  test "--config flag selects the config file" do
    Mix.Tasks.Arch.Check.run(["--config", "fixtures/arch_ok.exs"])

    assert_received {:mix_shell, :info, [msg]}
    assert msg =~ "All architecture rules passed."
  end

  test "--no-cache flag sets ExArch_NO_CACHE env var" do
    System.delete_env("ExArch_NO_CACHE")

    Mix.Tasks.Arch.Check.run(["--config", "fixtures/arch_ok.exs", "--no-cache"])

    assert System.get_env("ExArch_NO_CACHE") == "1"
  end

  test "ExArch_PROFILE=1 prints stats" do
    System.put_env("ExArch_PROFILE", "1")

    Mix.Tasks.Arch.Check.run(["--config", "fixtures/arch_ok.exs"])

    messages = flush_info_messages()
    assert Enum.any?(messages, &(&1 =~ "Stats:"))
  end

  test "default config path is arch.exs when no flags given" do
    # With no arch.exs in project root, Config.load! warns and returns empty config.
    # Empty config has no rules, so it passes.
    Mix.Tasks.Arch.Check.run([])

    assert_received {:mix_shell, :info, [msg]}
    assert msg =~ "All architecture rules passed."
  end

  defp flush_info_messages do
    flush_info_messages([])
  end

  defp flush_info_messages(acc) do
    receive do
      {:mix_shell, :info, [msg]} -> flush_info_messages([msg | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
