#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=scripts/release_common.sh
source "$REPO_ROOT/scripts/release_common.sh"

if [ ! -d "Obviewer.xcodeproj" ]; then
  "$REPO_ROOT/scripts/generate_xcode_project.sh"
fi

if [ "${OBVIEWER_SKIP_BUILD:-0}" != "1" ]; then
  "$REPO_ROOT/scripts/build_app.sh"
fi

APP_PATH="$(default_app_path)"
ZIP_PATH="$(signed_zip_path)"

verify_signed_app_bundle "$APP_PATH"
require_notary_profile

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

xcrun notarytool submit "$ZIP_PATH" \
  --keychain-profile "$OBVIEWER_NOTARY_KEYCHAIN_PROFILE" \
  --wait

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "Notarized and stapled $APP_PATH"
