defmodule ExArchUnit.BuilderTest do
  use ExUnit.Case, async: true

  alias ExArchUnit.Graph.Builder

  test "discovers umbrella apps from filesystem fallback scan" do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ex_arch_builder_fallback_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(Path.join(tmp_dir, "apps/app_one"))
    File.mkdir_p!(Path.join(tmp_dir, "apps/app_two"))
    File.mkdir_p!(Path.join(tmp_dir, "apps/not_a_project"))

    File.write!(
      Path.join(tmp_dir, "apps/app_one/mix.exs"),
      "defmodule AppOne.MixProject do end\n"
    )

    File.write!(
      Path.join(tmp_dir, "apps/app_two/mix.exs"),
      "defmodule AppTwo.MixProject do end\n"
    )

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    assert Builder.discover_umbrella_apps_from_filesystem(tmp_dir) == [:app_one, :app_two]
  end
end
