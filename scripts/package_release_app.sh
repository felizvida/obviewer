#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=scripts/release_common.sh
source "$REPO_ROOT/scripts/release_common.sh"

"$(dirname "$0")/build_app.sh"

APP_PATH="$(default_app_path)"
ZIP_PATH="$(signed_zip_path)"

verify_signed_app_bundle "$APP_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
echo "Created $ZIP_PATH"
