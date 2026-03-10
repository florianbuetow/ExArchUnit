# ExArchUnit

![Made with AI](https://img.shields.io/badge/Made%20with-AI-333333?labelColor=f00) ![Verified by Humans](https://img.shields.io/badge/Verified%20by-Humans-333333?labelColor=brightgreen) ![Coverage](https://img.shields.io/badge/Coverage-93.2%25-brightgreen)

Enforce architecture rules in Elixir projects — without touching production code. Define layer boundaries in a standalone `arch.exs` file, run `mix arch.check`, and get CI-friendly output. Rules live outside your application, so your production modules stay clean.

## Quick Start

**1. Add the dependency:**

```elixir
defp deps do
  [
    {:ex_arch_unit, "~> 0.1.0"}
  ]
end
```

**2. Create `arch.exs` next to `mix.exs`:**

```elixir
layers do
  layer :web, "MyAppWeb.*"
  layer :domain, "MyApp.Domain.*"

  allow :web, depends_on: [:domain]
  forbid :domain, depends_on: [:web]
end
```

**3. Run:**

```bash
mix arch.check
```

That's it. No test file needed. It enforces your `arch.exs` rules and exits with code 1 on violations. Add it to CI and you're done.

## Two Ways to Enforce Rules

### Option A: `mix arch.check` (recommended for most users)

Write your rules in `arch.exs` and run `mix arch.check`. This is the simplest path — one config file, one command. Covers `allow` and `forbid` layer rules.

```bash
mix arch.check                            # uses arch.exs
mix arch.check --config path/to/arch.exs  # custom config path
mix arch.check --no-cache                 # bypass graph cache
```

### Option B: ExUnit tests (when you need more)

Write a test file with `use ExArchUnit` when you need capabilities beyond what `arch.exs` offers:

- **Cycle detection** — `assert_no_cycles` isn't available in `arch.exs` yet
- **Ad-hoc rules** — one-off `forbid`/`allow` checks that don't belong in the global config
- **Test integration** — run architecture checks as part of `mix test`

```elixir
defmodule ArchitectureTest do
  use ExUnit.Case, async: true
  use ExArchUnit, config: "arch.exs"

  # Cycle detection (not available in arch.exs)
  test "domain has no cycles" do
    assert_no_cycles prefix: "MyApp.Domain.*"
  end

  # Ad-hoc rule outside the config
  test "controllers don't call repo directly" do
    forbid "MyAppWeb.Controllers.*", depends_on: "MyApp.Repo.*"
  end
end
```

```bash
mix test
```

Note: `use ExArchUnit` also auto-enforces your `arch.exs` layer rules during `setup_all` by default, so you don't need to duplicate them as tests.

## Features

- **`mix arch.check`** — enforce `arch.exs` rules with one command, no test file needed
- **ExUnit integration** — write architecture tests with `forbid`, `allow`, and `assert_no_cycles` when you need more
- **Config DSL** — declare layers and rules in `arch.exs`
- **Global graph caching** — graph built once per run via `:persistent_term`, cache-hit in milliseconds
- **Umbrella-aware** — analyzes all umbrella child apps by default
- **Deterministic output** — sorted, stable violation messages suitable for AI-agent feedback loops
- **BEAM-accurate** — dependencies extracted from compiled BEAM files via `:xref`, not source parsing

## Why Not Boundary?

[Boundary](https://github.com/sasa1977/boundary) enforces module boundaries at compile time using `use Boundary` attributes inside your production modules. This means architecture rules are scattered across your codebase and coupled to the modules they constrain.

ExArchUnit takes the opposite approach: **rules live entirely outside your production code** in a standalone `arch.exs` file. Your application modules don't know they're being checked. This means:

- No `use`, `import`, or module attributes added to production code
- Rules are centralized in one file, easy to review and change
- You can add or remove ExArchUnit without modifying a single application module
- Architecture rules can be enforced in CI without being a compile-time dependency

If you prefer compile-time enforcement baked into your modules, use Boundary. If you want rules separate from production code, use ExArchUnit.

## ExUnit API

These macros are available inside test modules that `use ExArchUnit`:

- `forbid/2` — fails when source modules depend on forbidden targets.
- `allow/2` — fails when source modules depend on anything outside the allow-list (self-references are always permitted).
- `assert_no_cycles/1` — fails when SCC cycles are found in selected modules.

`use ExArchUnit` also auto-enforces `arch.exs` layer rules during `setup_all`. Disable if needed:

```elixir
use ExArchUnit, config: "arch.exs", enforce_config_rules: false
```

## `arch.exs` DSL

Supported DSL entries:

- `layers do ... end`
- `layer :name, "Module.Pattern.*"`
- `allow :layer, depends_on: [:other_layer]`
- `forbid :layer, depends_on: [:other_layer]`
- `include "MyApp.*"` or `include ["MyApp.*", "Other.*"]`
- `exclude "MyApp.Legacy.*"` or list form
- `include_deps true | false` (default `false`)
- `include_behaviours true | false` (default `false`)
- `cache true | false` (default `true`)
- `builder :xref` (v0.1 only)

## Umbrella Support

In umbrella projects, ExArchUnit analyzes umbrella child apps by default.

App discovery strategy:

1. `Mix.Project.apps_paths/0` when available
2. Fallback filesystem scan of `apps/*/mix.exs` when needed

Set `include_deps true` if you explicitly want to include dependencies under `_build`.

## Reference

### Selector Semantics

Selectors are string-based and deterministic:

- `"MyApp.Domain.*"` matches module-name prefix `MyApp.Domain.`
- `"MyApp.*"` matches module-name prefix `MyApp.`
- `"MyApp.Domain.User"` matches exact module name

Regex selectors are not part of v0.1.

### Dependency Semantics

Default dependency source:

- `:xref` module-call edges from compiled BEAM files

Optional edge source:

- `@behaviour` edges when `include_behaviours true`

Not treated as dependencies in v0.1:

- Plain `alias` without effective calls
- `import` without effective calls

### Caching and Invalidation

ExArchUnit stores the graph in `:persistent_term` for fast read access.

The cache invalidates when:

- `arch.exs` content changes
- Any analyzed BEAM file mtime changes
- BEAM file count changes in an analyzed `ebin` directory
- Any filter option changes (`include`, `exclude`, `include_deps`, `include_behaviours`)

### Environment Variables

```bash
ExArchUnit_NO_CACHE=1 mix test         # force rebuild every time
ExArchUnit_PROFILE=1  mix test         # print graph build stats
ExArchUnit_PROFILE=1  mix arch.check   # also works with arch.check
```

### Performance

- Build graph once, evaluate many rules against in-memory adjacency
- Complexity around `O(N + E)` for graph work
- Small projects: ~300–900ms
- Medium projects: ~1–2.5s
- Large umbrellas: ~2–8s
- Cache hit: near-instant (typically tens of ms)

## Development

This project uses [just](https://github.com/casey/just) as a command runner. Run `just` to see all available recipes.

```bash
just init              # Install Hex dependencies from mix.lock
just build             # Compile source and generate ExDoc HTML
just clean             # Remove _build and fetched dependencies

just ci                # Format, test, and build
just test              # ExUnit suite with coverage and graph build profiling
just test-nocache      # Same as test but with graph cache disabled (forces xref rebuild)

just code-format       # Auto-format all source files
just code-benchmark    # Benchmark graph build on a synthetic umbrella
```

Tune benchmark size:

```bash
ExArchUnit_BENCH_APPS=6 ExArchUnit_BENCH_MODULES_PER_APP=120 just code-benchmark
```

### CI

GitHub Actions runs formatting, tests, and docs on every push. See [ci.yml](.github/workflows/ci.yml).

## License

MIT — see [LICENSE](LICENSE).
