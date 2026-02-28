# ExArch — Architecture Testing for Elixir

**Design & Implementation Document (v0.1)**

---

## 1. Goal

Provide an ArchUnit-like architecture testing tool for Elixir that:

- Works like normal unit tests (via ExUnit)
- Builds a dependency graph once per test run
- Enforces architectural rules via a DSL
- Scales to very large umbrella codebases
- Remains fast in repeated dev/AI-agent loops

**Non-goals (v0.1):**

- Runtime enforcement
- Compile-time compiler plugin
- Complex incremental graph diffing

---

## 2. User Experience

### Installation

Published on Hex.pm.

```elixir
defp deps do
  [
    {:ex_arch_unit, "~> 0.1.0"}
  ]
end
```

Users run:

```bash
mix deps.get
mix test
```

### Test Usage

```elixir
defmodule ArchitectureTest do
  use ExUnit.Case, async: true
  use ExArch, config: "arch.exs"

  test "domain does not depend on web" do
    forbid "MyApp.Domain.*", depends_on: "MyAppWeb.*"
  end

  test "no cycles in app" do
    assert_no_cycles prefix: "MyApp."
  end
end
```

Rules are simple one-liners. Graph building is invisible.

---

## 3. Configuration

### Location

`arch.exs` sits next to `mix.exs`.

**Reasoning:**

- Architecture config is read more often than build config
- Clear separation of concerns
- Easier discoverability for humans and AI tooling
- Avoids bloating `mix.exs`

### Example `arch.exs`

```elixir
layers do
  layer :web,    "MyAppWeb.*"
  layer :domain, "MyApp.Domain.*"
  layer :infra,  "MyApp.Infrastructure.*"

  allow :web,    depends_on: [:domain]
  forbid :domain, depends_on: [:web]
end
```

`arch.exs` is loaded and validated once at graph build time.

### DSL Evaluation Mechanism

`ExArch.Config.load!/1` prepends `import ExArch.Config.DSL` to the file
content and evaluates it via `Code.eval_string/3`. This injects the DSL
functions (`layers/1`, `layer/2`, `allow/2`, `forbid/2`, `include/1`,
`exclude/1`, `include_deps/1`, `include_behaviours/1`, `cache/1`,
`builder/1`) into scope without requiring any `use`, `import`, or
`require` inside `arch.exs`.

`ExArch.Config.DSL` accumulates state in the `Process` dictionary during
evaluation and returns the final `%ExArch.Config{}` via `collected_config/0`.

**Implementation:**

```elixir
# ExArch.Config
def load!(path) do
  config_path = Path.expand(path)
  DSL.reset!(%Config{path: config_path, source_hash: "missing"})

  source = File.read!(config_path)
  script = "import ExArch.Config.DSL\n" <> source
  _ = Code.eval_string(script, [], file: config_path)

  config = %{DSL.collected_config() | path: config_path, source_hash: sha256_file(config_path)}
  validate!(config)
end
```

This keeps `arch.exs` declarative and readable by non-Elixir tooling.
Validation errors in `arch.exs` are surfaced as `ArgumentError` exceptions
with descriptive messages.

---

## 4. Core Architecture

### Public API Layer

- `ExArch` — `use ExArch` macro, rule macros: `forbid/2`, `allow/2`, `assert_no_cycles/1`
- Injects `setup_all` with config rule auto-enforcement

### Engine Layer

Pure logic, no ExUnit dependency:

- `ExArch.Config` — loads and validates `arch.exs`
- `ExArch.Config.DSL` — DSL functions, accumulates config via `Process` dictionary
- `ExArch.Graph` — graph struct with integer-ID interning, SCC cycle detection
- `ExArch.Graph.Builder` — `:xref` isolation and BEAM discovery
- `ExArch.Graph.Cache` — `:persistent_term` cache with fingerprint invalidation
- `ExArch.Selector` — compiles and matches wildcard/exact module selectors
- `ExArch.Rule` — internal rule struct
- `ExArch.Rule.Evaluator` — rule evaluation with selector memoization
- `ExArch.Reporter` — deterministic violation formatting

### Dependency Extraction

Uses Erlang `:xref` to load compiled BEAM files.

**Why:**

- More accurate than source AST parsing
- Fast for large systems
- Reflects actual compiled dependencies, not textual imports

All `:xref` usage is fully isolated in `ExArch.Graph.Builder`. No other
module uses `:xref` directly.

---

## 5. Graph Build Strategy

### Critical Design Decision

The graph is built **once per test run**, not per test or per test module.

### Implementation

`use ExArch` injects:

```elixir
setup_all do
  config = ExArch.Config.load!(@ex_arch_config_path)
  {graph, stats} = ExArch.Graph.Cache.get_or_build(config)

  if @ex_arch_enforce_config_rules do
    ExArch.__assert_config_rules__(graph, config)
  end

  {:ok, graph: graph, arch_stats: stats, arch_config: config}
end
```

Rules access the graph and config from the ExUnit test context.
Layer rules defined in `arch.exs` are automatically evaluated during
`setup_all` unless `enforce_config_rules: false` is passed to `use ExArch`.

### Multi-Module Cache Interaction

When a project has multiple architecture test modules (e.g. one per
layer), each calls `setup_all` independently. The interaction with the
cache is as follows:

1. **First module** to run calls `Cache.get_or_build/1`. Cache is cold.
   `:xref` runs. Graph is built and stored in `:persistent_term`.
   Timing: full build time (see section 7).

2. **Subsequent modules** call `Cache.get_or_build/1`. Fingerprint
   matches. Graph is returned from `:persistent_term` in < 50 ms.

This means only the first test module pays the build cost per test run,
regardless of how many architecture test modules exist. This behaviour
must be documented clearly — users seeing inconsistent timing between
modules may otherwise assume a bug.

---

## 6. Caching Strategy (Scales to Large Codebases)

### Cache Storage

Use `:persistent_term` by default.

**Reasons:**

- Extremely fast reads (single ETS-like lookup, no copying)
- Graph is rarely rebuilt within a test run
- Ideal for build-once-per-run scenario

**Known tradeoffs to document:**

- `:persistent_term` is global to the BEAM node. If multiple test runs
  share a node (unusual but possible with some tooling), they share the
  cache. The fingerprint check handles correctness, but users should be
  aware of this scope.
- Writing to `:persistent_term` triggers a full GC on all schedulers.
  This is acceptable for a build-once-per-run scenario but would be
  unacceptable if the cache were written frequently.
- For large umbrella projects (2000–4000+ modules), the graph term can
  reach 10–50 MB. This is a one-time GC penalty on write, not on read.

### Cache Key

```elixir
{Mix.env(), Config.project_root(), Mix.Project.build_path(), Builder.project_apps()}
```

### Fingerprint (Invalidation Mechanism)

The cache entry stores:

```elixir
%{
  graph: graph,
  fingerprint: fingerprint,
  stats: stats
}
```

Fingerprint includes:

1. SHA-256 hash of `arch.exs` content (stored as `source_hash` on the config struct)
2. For each relevant `ebin` directory: `{dir_path, max_mtime, beam_count}`
3. Config filter fields that affect graph contents:
   - `include` selectors
   - `exclude` selectors
   - `include_deps` boolean
   - `include_behaviours` boolean

This ensures changing any filter option invalidates the cache even if
BEAM files and `arch.exs` text are unchanged.

If the stored fingerprint differs from the current one, the cache is
invalidated and the graph is rebuilt from scratch.

### Why This Works

Elixir recompilation always updates BEAM file mtimes. Therefore:

- Code changed → BEAM mtime changes → `max_mtime` changes → rebuild
- Module deleted → `beam_count` drops → rebuild
- Config changed → `arch.exs` hash changes → rebuild
- Filter option changed → fingerprint differs → rebuild
- Nothing changed → fingerprint matches → graph returned instantly

### `max_mtime` Tradeoff

The fingerprint uses `max_mtime` per ebin directory rather than per
BEAM file. This is an intentional simplicity tradeoff: any file change
in a directory causes a full rebuild, even if the changed file is
unrelated to the architecture under test. The alternative — hashing
every BEAM file — would make the fingerprint check itself expensive for
large codebases. For v0.1, `max_mtime` + `beam_count` is the correct
tradeoff.

### Escape Hatches

- `ExArch_NO_CACHE=1` → force rebuild regardless of fingerprint
- Optional future: `mix arch.clean`

---

## 7. Performance Targets

### Expected Build Times

| Project Size   | Modules    | Expected Build Time |
|----------------|------------|---------------------|
| Small Phoenix  | 200–400    | 300–900 ms          |
| Medium         | 800–1500   | 1–2.5 s             |
| Large Umbrella | 2000–4000+ | 2–8 s               |

Anything approaching 15s indicates an implementation inefficiency.

On cache hit: graph retrieval < 50 ms.

**Important:** These targets are engineering goals, not measured results.
They must be validated against benchmarks — including at least one
synthetic umbrella benchmark — before v0.1 is published. The benchmark
should be reproducible and committed to the repository so regressions
are detectable.

---

## 8. Large Codebase Considerations

To support very large systems:

- Never build per rule; never run `:xref` queries per rule
- Extract all edges once at build time
- Convert to internal adjacency map (see section 9)
- Precompile wildcard/glob selectors at rule registration time
- Memoize module selection queries within a test run

Graph traversal complexity target: O(N + E) where N = modules, E = edges.

---

## 9. Internal Graph Representation

Modules are represented as integer IDs internally for memory efficiency:

```elixir
%ExArch.Graph{
  module_to_id: %{module_atom => non_neg_integer()},
  id_to_module: %{non_neg_integer() => module_atom},
  adjacency:    %{non_neg_integer() => MapSet.t(non_neg_integer())}
}
```

- `module_to_id` / `id_to_module` — bidirectional mapping between atoms and integer IDs
- `adjacency` — dependency edges keyed by integer source ID, values are `MapSet` of integer target IDs
- Modules are sorted deterministically before ID assignment

Rules operate purely on this structure. No rule ever calls `:xref`.
The graph is immutable after construction.

---

## 10. Isolation of `:xref` Risk

All Erlang `:xref` query syntax is contained in one file:

```
ExArch.Graph.Builder
```

If `:xref` syntax or behaviour changes across OTP versions:

- Only one file is affected
- No leakage into the rule system
- Test coverage of `Builder` is sufficient to catch regressions

**Builder public API:**

```elixir
build(config) :: {graph, stats}
```

No other module in the library calls `:xref`.

---

## 11. Rule Evaluation Model

Three rule types are implemented in `ExArch.Rule.Evaluator`:

**`forbid(graph, config, source_selector, target_selector)`** — asserts no
module in the source set depends on any module in the target set.
Returns `:ok | {:error, [{source_module, target_module}]}`.

**`allow(graph, config, source_selector, target_selector)`** — asserts
modules in the source set depend **only** on modules in the target set
(plus self-references). Any dependency outside the allowed set is a violation.
Returns `:ok | {:error, [{source_module, target_module}]}`.

**`assert_no_cycles(graph, config, opts)`** — detects cycles via
Kosaraju's SCC algorithm on the subgraph restricted to selected modules.
Reports SCCs with size > 1 and single-node SCCs with self-loops.
Returns `:ok | {:error, [[module]]}`.

**`evaluate_layer_rules(graph, config)`** — evaluates all `allow`/`forbid`
rules defined in `arch.exs` and returns aggregated violations.

Selector resolution is memoized per graph/config combination via `Process`
dictionary.

Violations are formatted deterministically by `ExArch.Reporter`:

- Exact module names, sorted
- One violation per line: `SourceModule -> TargetModule`
- Cycle output: `A -> B -> C -> A`

Deterministic output is a first-class requirement: AI agents and
automated tools must be able to act on violation messages without
parsing ambiguous text.

---

## 12. Dev / AI-Agent Loop Optimisation

Expected usage pattern:

- Frequent test runs in a tight edit-check loop
- Code changes between runs, but not on every run

Optimisation approach:

- Fast fingerprint check (filesystem stat only, no BEAM parsing)
- Full rebuild only when BEAM mtimes or `arch.exs` change
- Graph persisted across all test modules in a run via `:persistent_term`
- Minimal filesystem scanning (directory-level, not per-file)

This makes the typical AI-agent loop — write code, run tests, read
violations, fix code — as fast as a fingerprint check on most iterations.

---

## 13. Future Enhancements (Post v0.1)

- Global graph build once per test suite (ExUnit suite callbacks)
- Incremental graph updates
- `mix arch.check` CLI for CI pipelines
- Graph visualisation export (DOT / SVG)
- Umbrella app boundary enforcement
- Behaviour-based architectural rules
- `mix arch.clean` to clear `:persistent_term` cache

---

## 14. Summary of Key Decisions

| # | Decision | Status |
|---|---|---|
| 1 | Works as ExUnit helper, not Mix task | ✓ Implemented |
| 2 | Graph built in `setup_all`, shared via cache across modules | ✓ Implemented — cache interaction documented |
| 3 | Config in `arch.exs`, evaluated via `import ExArch.Config.DSL` + `Code.eval_string` | ✓ Implemented |
| 4 | `:xref` fully isolated in `Graph.Builder` | ✓ Implemented |
| 5 | Graph cached in `:persistent_term` | ✓ Implemented — GC penalty and size tradeoffs documented |
| 6 | Invalidation via `arch.exs` hash + BEAM `max_mtime` + `beam_count` + config filter fields | ✓ Implemented — `max_mtime` tradeoff explicit |
| 7 | Designed for umbrella-scale performance | ✓ Implemented — synthetic benchmark via `mix arch.bench` |
| 8 | Rule DSL single-line readability | ✓ Implemented |

---

## Final Outcome

ExArch will provide:

- Architecture as an enforceable, testable contract
- Minimal cognitive overhead for rule authors
- Scalable performance for large Elixir systems, including umbrella apps
- Clean internal separation of concerns
- Safe, predictable cache invalidation with documented tradeoffs
- Deterministic violation output suitable for AI-agent feedback loops

This is a coherent, production-viable v0.1 design.
