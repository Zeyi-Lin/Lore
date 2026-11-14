#!/usr/bin/env bash
# Compiles and runs the Lora data-layer benchmark against the real model code.
# Output is the evidence behind docs/PERFORMANCE_PLAN.md.
set -euo pipefail
cd "$(dirname "$0")/../.."

mkdir -p .build/perf-bench
export CLANG_MODULE_CACHE_PATH="$PWD/.build/cache/clang"
export SWIFT_MODULECACHE_PATH="$PWD/.build/cache/swift"

swiftc -O -o .build/perf-bench/lora-perf-bench \
  scripts/perf-bench/main.swift \
  Sources/Lora/Store/Models.swift \
  Sources/Lora/Localization/Localization.swift

exec .build/perf-bench/lora-perf-bench
