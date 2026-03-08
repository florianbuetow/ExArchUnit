# ExArchUnit justfile

[private]
default: help

# List available recipes
help:
    @echo "Available recipes:"
    @echo ""
    @echo "    init              # Install Hex dependencies from mix.lock"
    @echo "    build             # Compile source and generate ExDoc HTML"
    @echo "    clean             # Remove _build and fetched dependencies"
    @echo ""
    @echo "    ci                # Format, test, and build"
    @echo "    test              # ExUnit suite with coverage and graph build profiling"
    @echo "    test-nocache      # Same as test but with graph cache disabled (forces xref rebuild)"
    @echo ""
    @echo "    code-format       # Auto-format all source files"
    @echo "    code-benchmark    # Benchmark graph build on a synthetic umbrella"

#
# ── Setup ──────────────────────────────────────────────────────────────

# Install Hex dependencies from mix.lock
init:
    mix deps.get

# Compile source and generate ExDoc HTML
build: clean init
    mix compile
    mix docs

# Remove _build and fetched dependencies
clean:
    mix clean
    mix deps.clean --all

#
# ── Test ───────────────────────────────────────────────────────────────

# Format, test, and build
ci: code-format test build

# ExUnit suite with coverage and graph build profiling
test:
    ExArch_PROFILE=1 mix test --cover

# Same as test but with graph cache disabled (forces xref rebuild)
test-nocache:
    ExArch_NO_CACHE=1 ExArch_PROFILE=1 mix test --cover

#
# ── Code Quality ───────────────────────────────────────────────────────

# Auto-format all source files
code-format:
    mix format

# Benchmark graph build on a synthetic umbrella
code-benchmark:
    mix arch.bench
