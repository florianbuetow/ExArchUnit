# Changelog

## [0.1.0] - 2026-02-28

### Added
- ExUnit-first architecture testing API via `use ExArchUnit`.
- Rule macros: `forbid/2`, `allow/2`, `assert_no_cycles/1`.
- Config DSL loaded from `arch.exs` with layer and rule validation.
- Automatic enforcement of config-defined layer rules during `setup_all`.
- Dependency graph extraction via isolated `:xref` builder.
- Integer-ID graph representation with deterministic module ordering.
- Cycle detection via Kosaraju's SCC algorithm.
- Global graph cache in `:persistent_term` with fingerprint-based invalidation.
- Cache invalidation on BEAM mtime changes, config hash changes, and filter option changes.
- `ExArchUnit_NO_CACHE=1` escape hatch to force rebuild.
- `ExArchUnit_PROFILE=1` to print graph build stats.
- Selector compilation and memoization for efficient rule evaluation.
- Optional `@behaviour` edge extraction via `include_behaviours(true)`.
- `include`/`exclude` module filters and `include_deps` option.
- Umbrella project support with `Mix.Project.apps_paths/0` and filesystem fallback.
- Deterministic violation reporting via `ExArchUnit.Reporter`.
- `mix arch.check` task to enforce `arch.exs` rules without a test file (`--config`, `--no-cache`).
- Reproducible synthetic umbrella benchmark via `mix arch.bench` (dev only).
- GitHub Actions CI workflow for formatting and tests.
