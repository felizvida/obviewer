#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_PATH="${OUTPUT:-$ROOT_DIR/build/SampleVault}"
PROFILE_NAME="${PROFILE:-showcase}"

cd "$ROOT_DIR"
swift run ObviewerFixtureTool --output "$OUTPUT_PATH" --profile "$PROFILE_NAME"
