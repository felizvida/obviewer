#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_NAME="${PROFILE:-benchmark}"
OUTPUT_FORMAT="${FORMAT:-text}"
BUDGET_PATH="${BUDGET:-}"
OUTPUT_PATH="${OUTPUT:-}"
CACHE_ROOT="$ROOT_DIR/build/.swiftpm-cache"
MODULE_CACHE_ROOT="$ROOT_DIR/build/.swiftpm-modulecache"
CLANG_CACHE_ROOT="$ROOT_DIR/build/.clang-modulecache"

cd "$ROOT_DIR"
mkdir -p "$CACHE_ROOT" "$MODULE_CACHE_ROOT" "$CLANG_CACHE_ROOT"
export XDG_CACHE_HOME="$CACHE_ROOT"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE_ROOT"
export CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_ROOT"

args=(--format "$OUTPUT_FORMAT")
if [[ -n "$OUTPUT_PATH" ]]; then
    args+=(--output "$OUTPUT_PATH")
fi
if [[ -n "$BUDGET_PATH" ]]; then
    args+=(--budget "$BUDGET_PATH")
fi

if [[ -n "${VAULT:-}" ]]; then
    swift run --disable-sandbox ObviewerBenchmarkTool --vault "$VAULT" "${args[@]}"
else
    swift run --disable-sandbox ObviewerBenchmarkTool --profile "$PROFILE_NAME" "${args[@]}"
fi
