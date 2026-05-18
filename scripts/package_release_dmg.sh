#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=scripts/release_common.sh
source "$REPO_ROOT/scripts/release_common.sh"

if [ ! -d "Obviewer.xcodeproj" ]; then
  "$REPO_ROOT/scripts/generate_xcode_project.sh"
fi

"$REPO_ROOT/scripts/build_app.sh"

APP_PATH="$(default_app_path)"
STAGING_DIR="$(mktemp -d "$REPO_ROOT/build/obviewer-dmg.XXXXXX")"
UNSIGNED_DMG_PATH="$(signed_dmg_path)"
FINAL_DMG_PATH="$UNSIGNED_DMG_PATH"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

verify_signed_app_bundle "$APP_PATH"

if [ -n "${OBVIEWER_NOTARY_KEYCHAIN_PROFILE:-}" ]; then
  OBVIEWER_SKIP_BUILD=1 "$REPO_ROOT/scripts/notarize_release_app.sh"
fi

rm -rf "$STAGING_DIR/Obviewer.app" "$STAGING_DIR/Applications"
ditto "$APP_PATH" "$STAGING_DIR/Obviewer.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$UNSIGNED_DMG_PATH" "$(notarized_dmg_path)"
hdiutil create \
  -volname "Obviewer" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$UNSIGNED_DMG_PATH"

if [ -n "${OBVIEWER_NOTARY_KEYCHAIN_PROFILE:-}" ]; then
  xcrun notarytool submit "$UNSIGNED_DMG_PATH" \
    --keychain-profile "$OBVIEWER_NOTARY_KEYCHAIN_PROFILE" \
    --wait
  xcrun stapler staple "$UNSIGNED_DMG_PATH"
  xcrun stapler validate "$UNSIGNED_DMG_PATH"

  FINAL_DMG_PATH="$(notarized_dmg_path)"
  mv "$UNSIGNED_DMG_PATH" "$FINAL_DMG_PATH"
fi

echo "Created $FINAL_DMG_PATH"
