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

if [ -n "${OBVIEWER_NOTARY_KEYCHAIN_PROFILE:-}" ] && ! is_adhoc_signing; then
  OBVIEWER_SKIP_BUILD=1 "$REPO_ROOT/scripts/notarize_release_app.sh"
fi

CONTENT_DIR="$STAGING_DIR/content"
MOUNT_DIR="$STAGING_DIR/mount"
RW_DMG="$STAGING_DIR/obviewer-rw.dmg"
mkdir -p "$CONTENT_DIR" "$MOUNT_DIR"

# Copy without resource forks, Finder info, extended attributes or ACLs: strict
# code signing rejects that detritus.
ditto --norsrc --noextattr --noacl "$APP_PATH" "$CONTENT_DIR/Obviewer.app"
ln -s /Applications "$CONTENT_DIR/Applications"
if is_adhoc_signing; then
  cp "$REPO_ROOT/docs/INSTALL.md" "$CONTENT_DIR/Read Me First - How to Install.md"
fi
verify_signed_app_bundle "$CONTENT_DIR/Obviewer.app"

# Build the image by copying into a fresh APFS volume (not `hdiutil create -srcfolder`,
# which left Finder information on bundle files), then compress it.
size_mb=$(( $(du -sk "$CONTENT_DIR" | cut -f1) / 1024 * 3 / 2 + 64 ))
hdiutil create -size "${size_mb}m" -fs APFS -volname "Obviewer" -ov "$RW_DMG" >/dev/null
hdiutil attach "$RW_DMG" -nobrowse -noautoopen -mountpoint "$MOUNT_DIR" >/dev/null
prepare_staging_volume "$MOUNT_DIR"
ditto --norsrc --noextattr --noacl "$CONTENT_DIR" "$MOUNT_DIR"
# Give volume-discovery services a moment to act, then clean and verify the staging
# volume itself, so a failure says which stage introduced it.
sleep 2
clean_staging_volume "$MOUNT_DIR"
sync
verify_signed_app_bundle "$MOUNT_DIR/Obviewer.app"
verify_volume_layout "$MOUNT_DIR"
hdiutil detach "$MOUNT_DIR" >/dev/null

rm -f "$UNSIGNED_DMG_PATH" "$(notarized_dmg_path)"
hdiutil convert "$RW_DMG" -format UDZO -ov -o "$UNSIGNED_DMG_PATH" >/dev/null

# The package only counts if the app inside the finished DMG verifies as produced.
verify_dmg "$UNSIGNED_DMG_PATH"

if [ -n "${OBVIEWER_NOTARY_KEYCHAIN_PROFILE:-}" ] && ! is_adhoc_signing; then
  xcrun notarytool submit "$UNSIGNED_DMG_PATH" \
    --keychain-profile "$OBVIEWER_NOTARY_KEYCHAIN_PROFILE" \
    --wait
  xcrun stapler staple "$UNSIGNED_DMG_PATH"
  xcrun stapler validate "$UNSIGNED_DMG_PATH"

  FINAL_DMG_PATH="$(notarized_dmg_path)"
  mv "$UNSIGNED_DMG_PATH" "$FINAL_DMG_PATH"
  verify_dmg "$FINAL_DMG_PATH"
fi

echo "Created $FINAL_DMG_PATH"
