# ExArch — Implementation Specification

## 0. Purpose

Implement an ArchUnit-like architecture testing library for Elixir that is consumed as **ExUnit tests**, builds a **module dependency graph** from the **current compiled BEAM artifacts**, and evaluates **architecture rules** quickly in short feedback loops (including coding-agent loops). Correctness requirement: analysis must reflect the **current version of the code** (not stale graph results).

---

## 1. User-Facing Behavior

### 1.1 Installation and usage

* Library is published on **Hex.pm** and hosted on **GitHub**.
* Users add dependency in `mix.exs`, run `mix deps.get`, then run `mix test`.
* Users define rules in an ExUnit test file, typically `test/architecture_test.exs`.

### 1.2 Primary UX goals

* Rules should read like one-liners.
* Graph build is invisible to rule authors.
* Failures look like normal ExUnit failures with readable violation lists.

### 1.3 Default configuration location

* `arch.exs` at the repository root alongside `mix.exs`.
* `use ExArch` defaults to `config: "arch.exs"` and auto-discovers it if not provided.

---

## 2. System Design Overview

### 2.1 Module layout

* `ExArch` (public macros, ExUnit integration)
* `ExArch.Config` (load/validate `arch.exs`)
* `ExArch.Config.DSL` (DSL functions for `arch.exs` evaluation, accumulates config via `Process` dictionary)
* `ExArch.Graph` (internal graph struct, integer-ID interning, SCC cycle detection)
* `ExArch.Graph.Builder` (**only module that talks to `:xref` and BEAM loading**)
* `ExArch.Graph.Cache` (global cache + invalidation)
* `ExArch.Selector` (compiles and matches wildcard/exact module selectors)
* `ExArch.Rule` (internal rule struct)
* `ExArch.Rule.Evaluator` (rule evaluation over graph, selector memoization)
* `ExArch.Reporter` (formats violations)

### 2.2 Strict boundaries

* `:xref` interaction and any Erlang query syntax lives only in `ExArch.Graph.Builder`.
* Rules operate only on `ExArch.Graph` in-memory representation.

---

## 3. Core Decision: ExUnit-first with shared fixture

### 3.1 `use ExArch` behavior

`use ExArch` injects:

* config load + validation (once per module)
* `setup_all` that obtains the graph from `ExArch.Graph.Cache.get_or_build/1`
* imports rule macros that read the graph from ExUnit context

### 3.2 Context contract

`setup_all` returns:

* `{:ok, graph: graph, arch_stats: stats, arch_config: config}`

The `arch_config` value is included so that rule macros can access the loaded config
(layer definitions, etc.) without reloading `arch.exs`.

Macros (e.g. `forbid/2`) must:

* take user selectors/options
* evaluate rule against `context[:graph]` and `context[:arch_config]`
* call `ExUnit.Assertions.flunk/1` with formatted violations when failing

If the ExUnit context is unavailable (e.g. called outside `setup_all`), macros
fall back to loading config and building/fetching the graph on demand via
`ExArch.Config.load!/1` and `ExArch.Graph.Cache.get_or_build/1`.

---

## 4. Dependency Graph Extraction (Correctness: “current code”)

### 4.1 Source of truth

* The dependency graph is derived from **compiled BEAM files** in `_build/<env>/lib/**/ebin/*.beam`.
* This ensures analysis is based on the effective compiled state.

### 4.2 Build precondition

* Under `mix test`, compilation normally happens before tests run.
* If BEAMs are missing, error clearly: “No BEAMs found; run `mix test` or `mix compile`.”

### 4.3 What counts as a dependency edge (v0.1 explicit definition)

To avoid ambiguity and keep trust high, v0.1 must clearly implement a conservative set:

**Edge types included**

* Remote module calls detectable through `:xref` call graph (primary, via `:xref.q(server, 'ME')`)
* `@behaviour` dependencies: extracted from BEAM file attributes via `:beam_lib.chunks/2`, enabled by `include_behaviours: true` in `arch.exs`. Both `:behaviour` and `:behavior` attribute keys are recognized.

**Edge types excluded (v0.1)**

* Pure `alias` usage (not a dependency unless invoked)
* `import` without calls
* Struct literal usage unless it implies a call edge via compiled code

Rationale: avoid “false” violations that come from non-semantic imports/aliases.

---

## 5. Graph Builder (`ExArch.Graph.Builder`)

### 5.1 Inputs

* `config` (layers, include/exclude, umbrella options)
* build environment `Mix.env()`
* discovered app roots and BEAM paths

### 5.2 Outputs

* `{graph, stats}` where:

  * `graph` is internal adjacency representation
  * `stats` includes timing and counts for profiling

### 5.3 Process (high level)

1. Discover BEAM files to analyze (see §6).
2. Start and load an `:xref` context with those BEAMs (implementation detail isolated here).
3. Extract call/dependency edges in bulk.
4. Normalize modules and build adjacency map.
5. Apply include/exclude filters.
6. Return graph and stats.

### 5.4 Stats to report

* `total_ms`
* `discover_beams_ms`
* `xref_load_ms`
* `extract_edges_ms`
* `normalize_ms`
* `modules_count`
* `edges_count`
* `cache_hit?` (set by cache layer)

Optional: enable printing stats when `ExArch_PROFILE=1`.

### 5.5 Determinism

* Sort modules and violation output to avoid flakiness.
* Ensure stable ordering across runs.

---

## 6. Large Codebase Support (Umbrella + performance)

### 6.1 Umbrella discovery

* Support umbrella projects by discovering apps and their `ebin` dirs.
* Use `Mix.Project.apps_paths/0` when available; fallback to scanning `apps/*/mix.exs` and mapping to `_build/.../lib/<app>/ebin`.

### 6.2 What to analyze by default

Default should analyze only:

* the project’s own apps (umbrella children / primary app)
  Not default:
* all dependencies in `_build` (too noisy and huge)

Provide config flags to include deps if desired:

* `include_deps: true | false` (default false)

### 6.3 Complexity target

* Build should be **O(N + E)** once edges are extracted.
* No per-rule scanning of all edges; precompute adjacency once.

### 6.4 Memory footprint

For very large graphs:

* Represent modules as integer IDs internally:

  * `id = module_index[module_atom]`
  * adjacency as `Map<int, MapSet<int>>` or sorted int lists
* Keep a reverse map `id_to_module` for reporting.

---

## 7. Selectors and Layer Semantics

### 7.1 Module selector syntax (v0.1)

Support string patterns:

* `"MyApp.Domain.*"` matches modules whose string name starts with `"MyApp.Domain."`
* `"MyApp.*"` matches `"MyApp."` prefix
* Exact `"MyApp.Domain.User"` matches that module only

No regex in v0.1 (optional later).

### 7.2 Normalization rules

* Convert module atoms to `"MyApp.Foo.Bar"` string form consistently.
* Internally store module as atom or integer ID; normalize inputs deterministically.
* Avoid `Elixir.` prefix confusion by using Elixir module atoms and `Module.split/1`/`Module.concat/1` conversions consistently.

### 7.3 Layer definitions

`arch.exs` may define:

* named layers: `layer :domain, "MyApp.Domain.*"`
* rule helpers: `allow :web, depends_on: [:domain]`, etc.

Implementation: layers compile to concrete module sets using selector matching over `graph.modules`.

---

## 8. Rule Engine

### 8.1 Rule types (v0.1)

All three rule types are shipped:

* `forbid <selector>, depends_on: <selector | layer>` — asserts no module in the source set depends on any module in the target set.
* `allow <selector>, depends_on: <selector | layer>` — asserts modules in the source set depend **only** on modules in the target set (plus self-references). Any dependency outside the allowed set is a violation.
* `assert_no_cycles prefix: <selector>` or `assert_no_cycles in: <selector/layer>` — asserts no dependency cycles exist among the selected modules.

Additionally, layer-level rules defined in `arch.exs` (via `allow/2` and `forbid/2` inside `layers do ... end`) are automatically evaluated during `setup_all` when `enforce_config_rules: true` (the default).

### 8.2 Evaluation algorithm

**`forbid`:**

* Resolve selectors to source module ID set `S` and target module ID set `T`.
* For each `s ∈ S`, compute `deps(s)` from adjacency map.
* Violation exists if `deps(s) ∩ T ≠ ∅`.

**`allow`:**

* Resolve selectors to source module ID set `S` and allowed target ID set `A`.
* For each `s ∈ S`, compute `deps(s)` from adjacency map.
* Violation exists for any `d ∈ deps(s)` where `d ∉ A` and `d ≠ s` (self-references are always permitted).

**Cycle detection:**

* Run Kosaraju's SCC algorithm on the subgraph restricted to selected module IDs.
* Report SCCs with size > 1 and single-node SCCs with a self-loop.

Selector resolution is memoized per graph/config combination via `Process` dictionary to avoid redundant computation across multiple rules in the same test run.

### 8.3 Violation output format

Must be compact, stable, greppable:

Example:

* Rule name / test name
* One violation per line:

  * `<SourceModule> -> <TargetModule>`
    Optionally include file path if known.

No fake line numbers.

---

## 9. Cache and Invalidation (Short feedback loop + correctness)

### 9.1 Cache goals

* Avoid repeated `:xref` load/build when nothing changed.
* Guarantee that if code/config changed, graph is rebuilt (no stale results).

### 9.2 Storage

* Use `:persistent_term` for fastest read.
* Store one entry per `{project, env}` key.

### 9.3 Cache key

Include:

* `Mix.env()`
* absolute project root
* build path (`_build/<env>`)
* umbrella app list (names)

### 9.4 Fingerprint (invalidation inputs)

Fingerprint incorporates:

1. `arch.exs` content hash (SHA-256, stored as `source_hash` on the config struct)
2. BEAM compilation state across relevant apps:

   * For each relevant `ebin` dir: `{dir_path, max_mtime, beam_count}`
3. Config filter fields that affect which modules/edges are included in the graph:

   * `include` selectors
   * `exclude` selectors
   * `include_deps` boolean
   * `include_behaviours` boolean

This ensures that changing any filter option invalidates the cache even if the
BEAM files and `arch.exs` text are unchanged.

If fingerprint differs, rebuild.

### 9.5 Fingerprint computation cost

* Computing `max_mtime` requires scanning BEAM files; for huge repos this is still typically cheaper than `:xref` load.
* Optimization allowed:

  * first check directory mtimes (cheap); if unchanged, skip deeper scan
  * or maintain per-dir cached stats in ETS

### 9.6 Concurrency safety

ExUnit can run async:

* Reads from `:persistent_term` are safe.
* Build must be guarded by a global lock so only one builder runs:

  * `:global.trans({:ExArch_build, key}, fn -> ... end)`
  * or ETS-based mutex

### 9.7 Escape hatches

* `ExArch_NO_CACHE=1` forces rebuild every time.
* Optional future: `mix arch.clean` clears cache.

### 9.8 “Current code” guarantee

This design ensures analysis is current because:

* Compilation produces new BEAM mtimes.
* Fingerprint detects changes and triggers rebuild.
* Config hash change triggers rebuild even without recompilation.

---

## 10. Configuration Loading (`arch.exs`)

### 10.1 Execution model

* `arch.exs` is evaluated as Elixir code (like `config/*.exs`), but must return a well-typed config struct or DSL block.
* Provide clear error messages on invalid config.

### 10.2 DSL implementation

`ExArch.Config.load!/1` prepends `import ExArch.Config.DSL` to the file content
and evaluates it via `Code.eval_string/3`. This injects the DSL functions
(`layers/1`, `layer/2`, `allow/2`, `forbid/2`, `include/1`, `exclude/1`,
`include_deps/1`, `include_behaviours/1`, `cache/1`, `builder/1`) into scope.

`ExArch.Config.DSL` accumulates state in the `Process` dictionary during
evaluation and returns the final `%ExArch.Config{}` via `collected_config/0`.

This keeps `arch.exs` declarative — users write:

```elixir
layers do
  layer :web, "MyAppWeb.*"
  layer :domain, "MyApp.Domain.*"

  allow :web, depends_on: [:domain]
  forbid :domain, depends_on: [:web]
end
```

No `use`, `import`, or `require` needed inside `arch.exs`.

### 10.3 Config fields (v0.1)

`%ExArch.Config{}` struct fields:

* `path`: absolute path to the loaded `arch.exs` file
* `source_hash`: SHA-256 hex digest of `arch.exs` content (or a hash of `{:default_config, path}` if file is missing)
* `layers`: `%{atom() => String.t()}` — layer name to selector pattern
* `layer_rules`: `[%ExArch.Rule{}]` — rules defined inside `layers do ... end` in `arch.exs`
* `include`: `[String.t()]` — selector whitelist (default `[]`, meaning include all)
* `exclude`: `[String.t()]` — selector blacklist (default `[]`)
* `include_deps`: `boolean()` — whether to analyze dependency BEAMs (default `false`)
* `include_behaviours`: `boolean()` — whether to add `@behaviour` edges (default `false`)
* `cache`: `boolean()` — whether to use `:persistent_term` caching (default `true`)
* `builder`: `atom()` — only `:xref` is supported in v0.1 (default `:xref`)

---

## 11. Build/CI/Release Hygiene

### 11.1 Repository

* GitHub repo with:

  * README with quick start and 2–3 example rules
  * license
  * changelog
  * CI workflow: `mix test`, formatting, Credo (optional)

### 11.2 Hex packaging

* Add metadata to `mix.exs`: `description`, `package`, `links`, `licenses`
* `mix hex.publish` and tag releases (`v0.1.0`, etc.)

### 11.3 Documentation

* ExDoc generation and publishing (GitHub Pages or HexDocs)
* Document:

  * what is included as a dependency edge
  * performance expectations
  * caching/invalidation model
  * how to force rebuild

---

## 12. Minimal Acceptance Criteria (v0.1)

1. A user can add dependency, write `test/architecture_test.exs`, and run `mix test`.
2. Graph is built once (or reused from cache) and is not rebuilt per test.
3. Cache invalidates when:

   * `arch.exs` changes
   * BEAM mtimes change in relevant ebin dirs
4. Works on umbrella projects (multiple apps).
5. `forbid` rule works and reports stable violation output.
6. `assert_no_cycles` works on selected prefix.
7. Performance: large codebases should typically build in low seconds and cache-hit runs should be near-instant.

---

## 13. Implementation Checklist (ordered)

1. Implement `%ExArch.Graph{}` + module ID interning.
2. Implement selector matcher and layer resolution.
3. Implement `ExArch.Config` loader (`arch.exs`) + validation.
4. Implement `ExArch.Graph.Builder` using `:xref` and bulk edge extraction.
5. Implement `ExArch.Graph.Cache` with fingerprint + locking.
6. Implement `ExArch.Rule.Evaluator` for `forbid` and SCC cycle detection.
7. Implement `ExArch` macros + injected `setup_all`.
8. Implement `ExArch.Reporter` formatting and deterministic ordering.
9. Add profiling stats + `ExArch_PROFILE=1`.
10. Add CI + docs + publish to Hex.

This document defines the required behavior, boundaries, and performance/correctness mechanisms to implement the tool for large codebases and short feedback loops.
