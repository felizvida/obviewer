#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_PATH="${OUTPUT:-$ROOT_DIR/build/SampleVault}"
PROFILE_NAME="${PROFILE:-showcase}"
CACHE_ROOT="$ROOT_DIR/build/.swiftpm-cache"
MODULE_CACHE_ROOT="$ROOT_DIR/build/.swiftpm-modulecache"
CLANG_CACHE_ROOT="$ROOT_DIR/build/.clang-modulecache"

cd "$ROOT_DIR"
mkdir -p "$CACHE_ROOT" "$MODULE_CACHE_ROOT" "$CLANG_CACHE_ROOT"
export XDG_CACHE_HOME="$CACHE_ROOT"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE_ROOT"
export CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_ROOT"
swift run --disable-sandbox ObviewerFixtureTool --output "$OUTPUT_PATH" --profile "$PROFILE_NAME"
