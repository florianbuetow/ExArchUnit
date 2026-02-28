# ExArchUnit

![Made with AI](https://img.shields.io/badge/Made%20with-AI-333333?labelColor=f00) ![Verified by Humans](https://img.shields.io/badge/Verified%20by-Humans-333333?labelColor=brightgreen) ![Coverage](https://img.shields.io/badge/Coverage-92.9%25-brightgreen)

ArchUnit-like architecture testing for Elixir. Define layer boundaries, forbid illegal dependencies, and detect cycles — all as normal ExUnit tests against compiled BEAM dependency graphs. Built for fast feedback loops in dev and AI-agent workflows.

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

**3. Add an architecture test:**

```elixir
defmodule ArchitectureTest do
  use ExUnit.Case, async: true
  use ExArch, config: "arch.exs"

  test "domain does not depend on web" do
    forbid "MyApp.Domain.*", depends_on: "MyAppWeb.*"
  end

  test "web only depends on domain" do
    allow "MyAppWeb.*", depends_on: "MyApp.Domain.*"
  end

  test "domain has no cycles" do
    assert_no_cycles prefix: "MyApp.Domain.*"
  end
end
```

**3b. Or skip the test file — just run the config rules directly:**

```bash
mix arch.check
```

**4. Run:**

```bash
mix test           # runs arch tests alongside your other tests
mix arch.check     # standalone config rule check (no test file needed)
```

## Features

- **ExUnit-first** — architecture rules are normal tests, run with `mix test`
- **`mix arch.check`** — enforce `arch.exs` rules without writing a test file
- **One-liner rules** — `forbid`, `allow`, and `assert_no_cycles` read like plain English
- **Config DSL** — declare layers and rules in `arch.exs`, auto-enforced on every test run
- **Global graph caching** — graph built once per run via `:persistent_term`, cache-hit in milliseconds
- **Umbrella-aware** — analyzes all umbrella child apps by default
- **Deterministic output** — sorted, stable violation messages suitable for AI-agent feedback loops
- **BEAM-accurate** — dependencies extracted from compiled BEAM files via `:xref`, not source parsing

## Public API

- `use ExArch, config: "arch.exs"` injects a `setup_all` that builds or reuses the graph.
- `forbid/2` fails when source modules depend on forbidden targets.
- `allow/2` fails when source modules depend on anything outside the allow-list (self-references are always permitted).
- `assert_no_cycles/1` fails when SCC cycles are found in selected modules.

By default, `use ExArch` also enforces layer rules declared in `arch.exs`.
Disable that for a module if needed:

```elixir
use ExArch, config: "arch.exs", enforce_config_rules: false
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

### `mix arch.check`

Evaluates config-defined layer rules without a test file:

```bash
mix arch.check                          # uses arch.exs
mix arch.check --config path/to/arch.exs
mix arch.check --no-cache               # bypass graph cache
```

### Environment Variables

```bash
ExArch_NO_CACHE=1 mix test         # force rebuild every time
ExArch_PROFILE=1  mix test         # print graph build stats
ExArch_PROFILE=1  mix arch.check   # also works with arch.check
```

### Performance

- Build graph once, evaluate many rules against in-memory adjacency
- Complexity around `O(N + E)` for graph work
- Small projects: ~300–900ms
- Medium projects: ~1–2.5s
- Large umbrellas: ~2–8s
- Cache hit: near-instant (typically tens of ms)

## Development

### Test

```bash
mix test            # 93 tests
mix test --cover    # with coverage report (92.9% total)
```

Run only the minimal smoke scenario:

```bash
mix test test/ex_arch/smoke_test.exs
```

### Test Coverage

| Module | Coverage |
|---|---|
| ExArch.Config.DSL | 100% |
| ExArch.Reporter | 100% |
| ExArch.Rule | 100% |
| ExArch.Selector | 100% |
| ExArch.Config | 96% |
| ExArch.Graph.Cache | 95% |
| ExArch.Rule.Evaluator | 94% |
| ExArch.Graph | 91% |
| ExArch | 88% |
| ExArch.Graph.Builder | 87% |
| **Total** | **92.9%** |

### Format

```bash
mix format
```

### Docs

```bash
mix docs
```

### Benchmark

Synthetic umbrella benchmark:

```bash
mix arch.bench
```

Tune benchmark size:

```bash
ExArch_BENCH_APPS=6 ExArch_BENCH_MODULES_PER_APP=120 mix arch.bench
```

Keep generated benchmark project:

```bash
ExArch_BENCH_KEEP_TMP=1 mix arch.bench
```

### CI

GitHub Actions runs formatting, tests, and docs on every push. See [ci.yml](.github/workflows/ci.yml).

## License

MIT — see [LICENSE](LICENSE).
